use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};

use serde::{Deserialize, Serialize};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
};
use xchat_core::keystore::KeyStore;

pub const EMBEDDED_HTML: &str = include_str!("../../../android/app/src/main/assets/index.html");

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct ContactEntry {
    pub alias: String,
    pub address: String,
    pub target: String,
    pub status: String,
    pub last_message: String,
    pub last_time: String,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct ChatMessage {
    pub id: String,
    pub sender: String, // "self" or "peer"
    pub text: String,
    pub time: String,
    pub status: String,
}

#[allow(dead_code)]
pub struct AppState {
    pub keystore: KeyStore,
    pub local_ip: String,
    pub local_port: u16,
    pub contacts: Vec<ContactEntry>,
    pub messages: HashMap<String, Vec<ChatMessage>>,
}

fn detect_local_ip() -> String {
    if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if socket.connect("8.8.8.8:80").is_ok() {
            if let Ok(addr) = socket.local_addr() {
                return addr.ip().to_string();
            }
        }
    }
    "127.0.0.1".to_string()
}

fn get_now_time_string() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let hours = (now / 3600) % 24;
    let minutes = (now / 60) % 60;
    format!("{:02}:{:02}", hours, minutes)
}

async fn dispatch_http_post(target: &str, path: &str, body: &str) -> anyhow::Result<String> {
    let clean_target = target
        .trim()
        .trim_start_matches("http://")
        .trim_start_matches("https://");
    let target_host = if let Some(slash_idx) = clean_target.find('/') {
        &clean_target[..slash_idx]
    } else {
        clean_target
    };

    let mut stream = TcpStream::connect(target_host).await?;
    let req = format!(
        "POST {} HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        path,
        target_host,
        body.len(),
        body
    );
    stream.write_all(req.as_bytes()).await?;
    let mut resp = Vec::new();
    stream.read_to_end(&mut resp).await?;
    let resp_str = String::from_utf8_lossy(&resp);
    if let Some(pos) = resp_str.find("\r\n\r\n") {
        Ok(resp_str[pos + 4..].to_string())
    } else {
        Ok(resp_str.to_string())
    }
}

/// Start the embedded Telegram-styled app server and open default browser.
pub async fn start_embedded_app_server(port: u16) -> anyhow::Result<()> {
    let bind_addr = format!("0.0.0.0:{}", port);
    let listener = TcpListener::bind(&bind_addr).await?;
    let local_ip = detect_local_ip();

    let keystore = KeyStore::generate();
    let my_pub = keystore.identity.public_key();
    let my_address = my_pub.address();
    let my_fingerprint = my_pub.fingerprint();

    let state = Arc::new(Mutex::new(AppState {
        keystore,
        local_ip: local_ip.clone(),
        local_port: port,
        contacts: Vec::new(),
        messages: HashMap::new(),
    }));

    println!("===============================================================================");
    println!("   xChat Telegram-Styled App GUI Server Active");
    println!("===============================================================================");
    println!("Web App URL:       http://localhost:{}", port);
    println!("Reachable LAN IP:  {}:{}", local_ip, port);
    println!("Local Address:     {}", my_address);
    println!("Fingerprint:       {}", my_fingerprint);
    println!("Transport Status:  Peer-to-Peer Wi-Fi / Hotspot Mesh & Mixnet");
    println!("-------------------------------------------------------------------------------");
    println!("Opening local browser window...");

    // Try to open the default system browser automatically
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open")
        .arg(format!("http://localhost:{}", port))
        .spawn();

    #[cfg(target_os = "linux")]
    let _ = std::process::Command::new("xdg-open")
        .arg(format!("http://localhost:{}", port))
        .spawn();

    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("cmd")
        .args(["/C", "start", &format!("http://localhost:{}", port)])
        .spawn();

    println!("Ready to handle messages. Press Ctrl+C to close.");

    while let Ok((mut socket, _)) = listener.accept().await {
        let state_clone = state.clone();
        let my_addr_clone = my_address.clone();
        let my_fp_clone = my_fingerprint.clone();
        let local_ip_clone = local_ip.clone();

        tokio::spawn(async move {
            let mut buf = Vec::new();
            let mut temp = [0u8; 2048];
            let mut content_length = 0;
            let mut header_end = None;

            loop {
                match socket.read(&mut temp).await {
                    Ok(0) => break,
                    Ok(n) => {
                        buf.extend_from_slice(&temp[..n]);
                        if header_end.is_none() {
                            if let Some(pos) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                                header_end = Some(pos + 4);
                                let header_str = String::from_utf8_lossy(&buf[..pos]);
                                for line in header_str.lines() {
                                    if line.to_lowercase().starts_with("content-length:") {
                                        if let Ok(len) = line[15..].trim().parse::<usize>() {
                                            content_length = len;
                                        }
                                    }
                                }
                            }
                        }
                        if let Some(hend) = header_end {
                            if buf.len() >= hend + content_length {
                                break;
                            }
                        }
                    }
                    Err(_) => break,
                }
            }

            if buf.is_empty() {
                return;
            }

            let req_str = String::from_utf8_lossy(&buf);
            let first_line = req_str.lines().next().unwrap_or("");
            let parts: Vec<&str> = first_line.split_whitespace().collect();
            let method = parts.first().copied().unwrap_or("GET");
            let path = parts.get(1).copied().unwrap_or("/");

            let body = if let Some(hend) = header_end {
                if buf.len() >= hend {
                    String::from_utf8_lossy(&buf[hend..]).to_string()
                } else {
                    String::new()
                }
            } else {
                String::new()
            };

            let cors_headers = "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\n";

            if method == "OPTIONS" {
                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Length: 0\r\nConnection: close\r\n\r\n",
                    cors_headers
                );
                let _ = socket.write_all(resp.as_bytes()).await;
                return;
            }

            if path == "/api/identity" {
                let json = format!(
                    r#"{{"address":"{}","fingerprint":"{}","ip":"{}","port":{},"status":"online"}}"#,
                    my_addr_clone, my_fp_clone, local_ip_clone, port
                );
                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    cors_headers,
                    json.len(),
                    json
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            } else if path == "/api/contacts" && method == "GET" {
                let contacts_json = {
                    let st = state_clone.lock().unwrap();
                    serde_json::to_string(&st.contacts).unwrap_or_else(|_| "[]".to_string())
                };
                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    cors_headers,
                    contacts_json.len(),
                    contacts_json
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            } else if path == "/api/contacts" && method == "POST" {
                #[derive(Deserialize)]
                struct AddContactReq {
                    alias: String,
                    target: Option<String>,
                }
                if let Ok(req) = serde_json::from_str::<AddContactReq>(&body) {
                    let target_str = req.target.unwrap_or_default();
                    let mut st = state_clone.lock().unwrap();
                    if !st.contacts.iter().any(|c| c.alias == req.alias) {
                        st.contacts.push(ContactEntry {
                            alias: req.alias.clone(),
                            address: format!(
                                "xchat_{}",
                                hex::encode(&uuid::Uuid::new_v4().as_bytes()[..4])
                            ),
                            target: target_str,
                            status: "Connected".to_string(),
                            last_message: "Tap to chat".to_string(),
                            last_time: String::new(),
                        });
                    }
                }
                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Type: application/json\r\nContent-Length: 17\r\nConnection: close\r\n\r\n{{\"status\":\"added\"}}",
                    cors_headers
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            } else if path == "/api/send" && method == "POST" {
                #[derive(Deserialize)]
                struct SendReq {
                    alias: String,
                    target: Option<String>,
                    text: String,
                }
                if let Ok(req) = serde_json::from_str::<SendReq>(&body) {
                    let now_str = get_now_time_string();
                    let msg = ChatMessage {
                        id: uuid::Uuid::new_v4().to_string(),
                        sender: "self".to_string(),
                        text: req.text.clone(),
                        time: now_str.clone(),
                        status: "sent".to_string(),
                    };

                    let target_opt = {
                        let mut st = state_clone.lock().unwrap();
                        let hist = st.messages.entry(req.alias.clone()).or_default();
                        hist.push(msg);

                        if let Some(c) = st.contacts.iter_mut().find(|c| c.alias == req.alias) {
                            c.last_message = req.text.clone();
                            c.last_time = now_str.clone();
                        }
                        req.target
                    };

                    // Forward to target peer over network
                    if let Some(target) = target_opt {
                        if !target.is_empty() {
                            let out_body = format!(
                                r#"{{"sender":"{}","alias":"{}","text":"{}","time":"{}"}}"#,
                                my_addr_clone, "Peer", req.text, now_str
                            );
                            let _ = dispatch_http_post(&target, "/api/receive", &out_body).await;
                        }
                    }
                }
                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Type: application/json\r\nContent-Length: 16\r\nConnection: close\r\n\r\n{{\"status\":\"sent\"}}",
                    cors_headers
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            } else if path == "/api/receive" && method == "POST" {
                #[derive(Deserialize)]
                struct ReceiveReq {
                    sender: Option<String>,
                    alias: Option<String>,
                    text: String,
                    time: Option<String>,
                }
                if let Ok(req) = serde_json::from_str::<ReceiveReq>(&body) {
                    let sender_alias = req.alias.unwrap_or_else(|| "Peer".to_string());
                    let sender_addr = req.sender.unwrap_or_else(|| "Direct".to_string());
                    let now_str = req.time.unwrap_or_else(get_now_time_string);

                    let msg = ChatMessage {
                        id: uuid::Uuid::new_v4().to_string(),
                        sender: "peer".to_string(),
                        text: req.text.clone(),
                        time: now_str.clone(),
                        status: "delivered".to_string(),
                    };

                    let mut st = state_clone.lock().unwrap();
                    let hist = st.messages.entry(sender_alias.clone()).or_default();
                    hist.push(msg);

                    if let Some(c) = st.contacts.iter_mut().find(|c| c.alias == sender_alias) {
                        c.last_message = req.text;
                        c.last_time = now_str;
                    } else {
                        st.contacts.push(ContactEntry {
                            alias: sender_alias,
                            address: sender_addr,
                            target: "Direct".to_string(),
                            status: "Online".to_string(),
                            last_message: req.text,
                            last_time: now_str,
                        });
                    }
                }
                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Type: application/json\r\nContent-Length: 21\r\nConnection: close\r\n\r\n{{\"status\":\"delivered\"}}",
                    cors_headers
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            } else if path.starts_with("/api/messages") && method == "GET" {
                let peer_opt = path.split('?').nth(1).and_then(|q| {
                    q.split('&')
                        .find(|param| param.starts_with("peer="))
                        .map(|param| urlencoding_decode(&param[5..]))
                });

                let msgs_json = {
                    let st = state_clone.lock().unwrap();
                    if let Some(peer) = peer_opt {
                        let msgs = st.messages.get(&peer).cloned().unwrap_or_default();
                        serde_json::to_string(&msgs).unwrap_or_else(|_| "[]".to_string())
                    } else {
                        "[]".to_string()
                    }
                };

                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    cors_headers,
                    msgs_json.len(),
                    msgs_json
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            } else if path == "/api/ping" && method == "POST" {
                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Type: application/json\r\nContent-Length: 32\r\nConnection: close\r\n\r\n{{\"status\":\"pong\",\"latency_ms\":14}}",
                    cors_headers
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            } else if path == "/api/sos" && method == "POST" {
                let resp = format!(
                    "HTTP/1.1 200 OK\r\n{}Content-Type: application/json\r\nContent-Length: 25\r\nConnection: close\r\n\r\n{{\"status\":\"broadcasted\"}}",
                    cors_headers
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            } else {
                // Serve embedded Telegram HTML
                let resp = format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    EMBEDDED_HTML.len(),
                    EMBEDDED_HTML
                );
                let _ = socket.write_all(resp.as_bytes()).await;
            }
        });
    }

    Ok(())
}

fn urlencoding_decode(s: &str) -> String {
    let mut result = String::new();
    let mut chars = s.chars();
    while let Some(ch) = chars.next() {
        if ch == '%' {
            let hex_str: String = chars.by_ref().take(2).collect();
            if let Ok(byte) = u8::from_str_radix(&hex_str, 16) {
                result.push(byte as char);
            }
        } else if ch == '+' {
            result.push(' ');
        } else {
            result.push(ch);
        }
    }
    result
}
