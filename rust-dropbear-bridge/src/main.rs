//! Tailnet TCP 22 -> local Dropbear, plus a one-button Wake-on-LAN page.
//!
//! An auth key is accepted only once, on stdin, with --auth-key-stdin. It is
//! never written by this program; the persistent state file contains the node
//! identity after registration.
use std::{error::Error, path::PathBuf, process::Command};

use tailscale::{Config, Device};
use tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt, copy_bidirectional},
    net::TcpStream,
    task::spawn,
};

const WAKE_PAGE: &str = include_str!("wake.html");
const MANIFEST: &str = r##"{"name":"Wake PC","short_name":"Wake PC","start_url":"/","display":"standalone","background_color":"#101014","theme_color":"#101014"}"##;

struct Args {
    state: PathBuf,
    port: u16,
    http_port: u16,
    auth_key_stdin: bool,
}

fn usage() -> ! {
    eprintln!(
        "usage: yun-tailssh-bridge --state PATH [--port 22] [--http-port 80] [--auth-key-stdin]"
    );
    std::process::exit(2);
}

fn args() -> Args {
    let mut state = None;
    let mut port = 22;
    let mut http_port = 80;
    let mut auth_key_stdin = false;
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--state" => state = it.next().map(PathBuf::from),
            "--port" => port = it.next().and_then(|s| s.parse().ok()).unwrap_or_else(|| usage()),
            "--http-port" => {
                http_port = it.next().and_then(|s| s.parse().ok()).unwrap_or_else(|| usage())
            }
            "--auth-key-stdin" => auth_key_stdin = true,
            "--help" | "-h" => usage(),
            _ => usage(),
        }
    }
    Args { state: state.unwrap_or_else(|| usage()), port, http_port, auth_key_stdin }
}

fn one_time_auth_key(enabled: bool) -> Result<Option<String>, Box<dyn Error>> {
    if !enabled {
        return Ok(None);
    }
    let mut key = String::new();
    std::io::stdin().read_line(&mut key)?;
    let key = key.trim().to_owned();
    if key.is_empty() {
        return Err("empty auth key on stdin".into());
    }
    Ok(Some(key))
}

fn send_wol() -> Result<(), String> {
    match Command::new("/usr/bin/wol").status() {
        Ok(status) if status.success() => Ok(()),
        Ok(status) => Err(format!("wol exited {status}")),
        Err(err) => Err(format!("wol failed: {err}")),
    }
}

fn request_target(head: &str) -> Option<(&str, &str)> {
    let line = head.lines().next()?;
    let mut parts = line.split_whitespace();
    Some((parts.next()?, parts.next()?))
}

async fn write_http<S: AsyncWrite + Unpin>(
    stream: &mut S,
    status: &str,
    content_type: &str,
    body: &[u8],
) -> Result<(), Box<dyn Error>> {
    let header = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
        body.len()
    );
    stream.write_all(header.as_bytes()).await?;
    stream.write_all(body).await?;
    Ok(())
}

async fn read_http_head<S: AsyncRead + Unpin>(stream: &mut S) -> Result<String, Box<dyn Error>> {
    let mut buf = Vec::with_capacity(1024);
    let mut tmp = [0u8; 512];
    loop {
        let n = stream.read(&mut tmp).await?;
        if n == 0 {
            break;
        }
        buf.extend_from_slice(&tmp[..n]);
        if buf.windows(4).any(|window| window == b"\r\n\r\n") || buf.len() > 8192 {
            break;
        }
    }
    Ok(String::from_utf8_lossy(&buf).into_owned())
}

async fn handle_http<S>(mut stream: S) -> Result<(), Box<dyn Error>>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let head = read_http_head(&mut stream).await?;
    let Some((method, target)) = request_target(&head) else {
        return write_http(&mut stream, "400 Bad Request", "text/plain; charset=utf-8", b"bad request\n").await;
    };
    let path = target.split('?').next().unwrap_or(target);

    match (method, path) {
        ("GET" | "HEAD", "/") | ("GET" | "HEAD", "/index.html") => {
            let body = if method == "HEAD" { b"".as_slice() } else { WAKE_PAGE.as_bytes() };
            write_http(&mut stream, "200 OK", "text/html; charset=utf-8", body).await
        }
        ("GET", "/manifest.json") => {
            write_http(&mut stream, "200 OK", "application/manifest+json", MANIFEST.as_bytes()).await
        }
        ("POST", "/wol") => {
            match tokio::task::spawn_blocking(send_wol).await {
                Ok(Ok(())) => {
                    eprintln!("wake UI sent WoL");
                    write_http(
                        &mut stream,
                        "200 OK",
                        "text/plain; charset=utf-8",
                        b"PC wake sent\n",
                    )
                    .await
                }
                Ok(Err(err)) => {
                    eprintln!("wake UI wol failed: {err}");
                    write_http(
                        &mut stream,
                        "500 Internal Server Error",
                        "text/plain; charset=utf-8",
                        format!("{err}\n").as_bytes(),
                    )
                    .await
                }
                Err(err) => {
                    write_http(
                        &mut stream,
                        "500 Internal Server Error",
                        "text/plain; charset=utf-8",
                        format!("{err}\n").as_bytes(),
                    )
                    .await
                }
            }
        }
        _ => write_http(&mut stream, "404 Not Found", "text/plain; charset=utf-8", b"not found\n").await,
    }
}

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn Error>> {
    let args = args();
    let auth_key = one_time_auth_key(args.auth_key_stdin)?;

    let mut config = Config::default_with_key_file(&args.state).await?;
    let hostname = std::env::var("TS_HOSTNAME").unwrap_or_else(|_| "yun".to_owned());
    config.requested_hostname = Some(hostname);
    let dev = Device::new(&config, auth_key).await?;
    let ip = dev.ipv4_addr().await?;
    let ssh_addr = (ip, args.port).into();
    let ssh_listener = dev.tcp_listen(ssh_addr).await?;
    eprintln!("tailnet SSH bridge listening on {ssh_addr}");

    if args.http_port != 0 {
        let http_addr = (ip, args.http_port).into();
        let http_listener = dev.tcp_listen(http_addr).await?;
        eprintln!("tailnet wake UI listening on {http_addr}");
        spawn(async move {
            loop {
                match http_listener.accept().await {
                    Ok(stream) => {
                        spawn(async move {
                            if let Err(err) = handle_http(stream).await {
                                eprintln!("wake UI request ended: {err}");
                            }
                        });
                    }
                    Err(err) => eprintln!("wake UI accept failed: {err}"),
                }
            }
        });
    }

    loop {
        let tailnet = ssh_listener.accept().await?;
        spawn(async move {
            let mut local = match TcpStream::connect(("127.0.0.1", 22)).await {
                Ok(s) => s,
                Err(e) => {
                    eprintln!("local Dropbear connection failed: {e}");
                    return;
                }
            };
            let mut tailnet = tailnet;
            if let Err(e) = copy_bidirectional(&mut tailnet, &mut local).await {
                eprintln!("SSH stream ended: {e}");
            }
        });
    }
}
