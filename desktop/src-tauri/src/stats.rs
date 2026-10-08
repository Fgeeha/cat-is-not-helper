//! Статистика тапов. Формат файла совместим с нативной macOS-версией:
//! дни по ключу yyyy-MM-dd, часы, суммарные счётчики, firstLaunch в секундах
//! от 2001-01-01 (эпоха Apple).

use std::collections::{HashMap, VecDeque};
use std::time::{Duration, Instant};

use chrono::{Datelike, Duration as ChronoDuration, Local, NaiveDate, Timelike};
use serde::{Deserialize, Serialize};

use crate::paths;

const APPLE_EPOCH_OFFSET: f64 = 978_307_200.0;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DayStats {
    #[serde(default)]
    pub keys: u64,
    #[serde(default)]
    pub clicks: u64,
    #[serde(default = "zero_hours")]
    pub hourly: Vec<u64>,
}

fn zero_hours() -> Vec<u64> {
    vec![0; 24]
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct StatsData {
    pub days: HashMap<String, DayStats>,
    pub total_keys: u64,
    pub total_clicks: u64,
    pub pets: u64,
    pub feeds: u64,
    pub screenshots: u64,
    #[serde(rename = "bestCPM")]
    pub best_cpm: u64,
    /// Секунды от 2001-01-01 UTC — как кодирует Date в Swift.
    pub first_launch: f64,
}

impl Default for StatsData {
    fn default() -> Self {
        let now_unix = chrono::Utc::now().timestamp() as f64;
        Self {
            days: HashMap::new(),
            total_keys: 0,
            total_clicks: 0,
            pets: 0,
            feeds: 0,
            screenshots: 0,
            best_cpm: 0,
            first_launch: now_unix - APPLE_EPOCH_OFFSET,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DayPoint {
    pub label: String,
    pub keys: u64,
    pub is_today: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub today_keys: u64,
    pub today_clicks: u64,
    pub cpm: u64,
    pub session_keys: u64,
    pub total_keys: u64,
    pub total_clicks: u64,
    pub best_cpm: u64,
    pub pets: u64,
    pub feeds: u64,
    pub screenshots: u64,
    pub streak: u32,
    pub active_days: usize,
    pub average_per_active_day: u64,
    pub last14: Vec<DayPoint>,
    pub hourly: Vec<u64>,
    pub best_day: Option<DayPoint>,
    pub first_launch: String,
}

pub struct StatsStore {
    pub data: StatsData,
    recent: VecDeque<Instant>,
    cpm: u64,
    session_keys: u64,
    dirty: bool,
    last_save: Instant,
}

fn day_key(date: NaiveDate) -> String {
    date.format("%Y-%m-%d").to_string()
}

fn short_label(date: NaiveDate) -> String {
    date.format("%d.%m").to_string()
}

impl StatsStore {
    pub fn load() -> Self {
        let data = std::fs::read(paths::stats_file())
            .ok()
            .and_then(|raw| serde_json::from_slice::<StatsData>(&raw).ok())
            .unwrap_or_default();
        Self {
            data,
            recent: VecDeque::new(),
            cpm: 0,
            session_keys: 0,
            dirty: false,
            last_save: Instant::now(),
        }
    }

    pub fn save(&mut self) {
        if let Ok(raw) = serde_json::to_vec(&self.data) {
            let _ = std::fs::write(paths::stats_file(), raw);
        }
        self.dirty = false;
        self.last_save = Instant::now();
    }

    fn today_mut(&mut self) -> &mut DayStats {
        let key = day_key(Local::now().date_naive());
        self.data.days.entry(key).or_default()
    }

    pub fn record_key(&mut self) {
        let hour = Local::now().hour() as usize;
        {
            let day = self.today_mut();
            day.keys += 1;
            if day.hourly.len() != 24 {
                day.hourly = vec![0; 24];
            }
            day.hourly[hour] += 1;
        }
        self.data.total_keys += 1;
        self.session_keys += 1;
        let now = Instant::now();
        self.recent.push_back(now);
        self.trim(now);
        self.cpm = self.recent.len() as u64;
        if self.cpm > self.data.best_cpm {
            self.data.best_cpm = self.cpm;
        }
        self.dirty = true;
    }

    pub fn record_click(&mut self) {
        self.today_mut().clicks += 1;
        self.data.total_clicks += 1;
        self.dirty = true;
    }

    pub fn record_pet(&mut self) {
        self.data.pets += 1;
        self.dirty = true;
    }

    pub fn record_feed(&mut self) {
        self.data.feeds += 1;
        self.dirty = true;
    }

    pub fn record_screenshot(&mut self) {
        self.data.screenshots += 1;
        self.dirty = true;
    }

    /// Раз в секунду: пересчёт скорости и отложенное сохранение.
    pub fn tick(&mut self) -> u64 {
        let now = Instant::now();
        self.trim(now);
        self.cpm = self.recent.len() as u64;
        if self.dirty && now.duration_since(self.last_save) > Duration::from_secs(3) {
            self.save();
        }
        self.cpm
    }

    fn trim(&mut self, now: Instant) {
        while let Some(front) = self.recent.front() {
            if now.duration_since(*front) > Duration::from_secs(60) {
                self.recent.pop_front();
            } else {
                break;
            }
        }
    }

    pub fn cpm(&self) -> u64 {
        self.cpm
    }

    pub fn today(&self) -> DayStats {
        self.data
            .days
            .get(&day_key(Local::now().date_naive()))
            .cloned()
            .unwrap_or_default()
    }

    fn keys_on(&self, date: NaiveDate) -> u64 {
        self.data.days.get(&day_key(date)).map(|d| d.keys).unwrap_or(0)
    }

    pub fn streak(&self) -> u32 {
        let mut date = Local::now().date_naive();
        if self.keys_on(date) == 0 {
            date -= ChronoDuration::days(1);
        }
        let mut count = 0;
        while self.keys_on(date) > 0 {
            count += 1;
            date -= ChronoDuration::days(1);
        }
        count
    }

    pub fn snapshot(&self) -> Snapshot {
        let today_date = Local::now().date_naive();
        let today = self.today();
        let last14 = (0..14)
            .rev()
            .map(|offset| {
                let date = today_date - ChronoDuration::days(offset);
                DayPoint {
                    label: short_label(date),
                    keys: self.keys_on(date),
                    is_today: offset == 0,
                }
            })
            .collect();
        let best_day = self
            .data
            .days
            .iter()
            .filter(|(_, d)| d.keys > 0)
            .max_by_key(|(_, d)| d.keys)
            .and_then(|(k, d)| {
                NaiveDate::parse_from_str(k, "%Y-%m-%d").ok().map(|date| DayPoint {
                    label: short_label(date),
                    keys: d.keys,
                    is_today: date == today_date,
                })
            });
        let active_days = self.data.days.values().filter(|d| d.keys > 0).count();
        let first_launch_unix = (self.data.first_launch + APPLE_EPOCH_OFFSET) as i64;
        let first_launch = chrono::DateTime::from_timestamp(first_launch_unix, 0)
            .map(|dt| dt.with_timezone(&Local).format("%d.%m.%Y").to_string())
            .unwrap_or_default();
        let mut hourly = today.hourly.clone();
        hourly.resize(24, 0);
        Snapshot {
            today_keys: today.keys,
            today_clicks: today.clicks,
            cpm: self.cpm,
            session_keys: self.session_keys,
            total_keys: self.data.total_keys,
            total_clicks: self.data.total_clicks,
            best_cpm: self.data.best_cpm,
            pets: self.data.pets,
            feeds: self.data.feeds,
            screenshots: self.data.screenshots,
            streak: self.streak(),
            active_days,
            average_per_active_day: if active_days == 0 { 0 } else { self.data.total_keys / active_days as u64 },
            last14,
            hourly,
            best_day,
            first_launch,
        }
    }
}

// Чтобы компилятор не ругался на неиспользуемый импорт в будущих правках.
#[allow(dead_code)]
fn _weekday(date: NaiveDate) -> u32 {
    date.weekday().number_from_monday()
}
