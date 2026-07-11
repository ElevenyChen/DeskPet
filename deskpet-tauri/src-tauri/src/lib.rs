use serde::Serialize;

#[derive(Serialize)]
struct ScreenSize {
    width: u32,
    height: u32,
}

#[tauri::command]
fn get_screen_size() -> ScreenSize {
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        let output = Command::new("system_profiler")
            .args(["SPDisplaysDataType"])
            .output();
        if let Ok(out) = output {
            let text = String::from_utf8_lossy(&out.stdout);
            for line in text.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("Resolution:") || trimmed.starts_with("UI Looks like:") {
                    let parts: Vec<&str> = trimmed.split_whitespace().collect();
                    for (i, p) in parts.iter().enumerate() {
                        if *p == "x" && i > 0 && i + 1 < parts.len() {
                            if let (Ok(w), Ok(h)) = (parts[i - 1].parse::<u32>(), parts[i + 1].parse::<u32>()) {
                                return ScreenSize { width: w, height: h };
                            }
                        }
                    }
                }
            }
        }
    }
    #[cfg(target_os = "windows")]
    {
        use std::process::Command;
        let output = Command::new("wmic")
            .args(["path", "Win32_VideoController", "get", "CurrentHorizontalResolution,CurrentVerticalResolution", "/format:list"])
            .output();
        if let Ok(out) = output {
            let text = String::from_utf8_lossy(&out.stdout);
            let mut w = 0u32;
            let mut h = 0u32;
            for line in text.lines() {
                if let Some(val) = line.strip_prefix("CurrentHorizontalResolution=") {
                    w = val.trim().parse().unwrap_or(0);
                }
                if let Some(val) = line.strip_prefix("CurrentVerticalResolution=") {
                    h = val.trim().parse().unwrap_or(0);
                }
            }
            if w > 0 && h > 0 {
                return ScreenSize { width: w, height: h };
            }
        }
    }
    ScreenSize { width: 1920, height: 1080 }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_screen_size])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
