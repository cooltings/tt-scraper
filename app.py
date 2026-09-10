import os
import json
import shutil
import threading
import re
from datetime import datetime, date
import customtkinter as ctk
from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

PROFILE_DIR = os.path.join(os.getcwd(), "MyCollegeProfile")
DATA_FILE = "schedule_cache.json"
WEEKS_TO_FETCH = 4

# --- Date Parsing Helper ---
def parse_date_range_string(date_str):
    """Parses strings like '7 to 13 September 2026' or '28 August to 3 September 2026'"""
    try:
        # Clean up whitespace and non-breaking spaces
        clean_str = re.sub(r'\s+', ' ', date_str).strip()
        
        # Match pattern: [Day] to [Day] [Month] [Year] or [Day] [Month] to [Day] [Month] [Year]
        match_full = re.search(r'(\d{1,2})\s+to\s+(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})', clean_str)
        if match_full:
            start_day, end_day, month_name, year_str = match_full.groups()
            year = int(year_str)
            # Parse month
            dt_start = datetime.strptime(f"{start_day} {month_name} {year}", "%d %B %Y").date()
            dt_end = datetime.strptime(f"{end_day} {month_name} {year}", "%d %B %Y").date()
            return dt_start, dt_end
            
        match_split_month = re.search(r'(\d{1,2})\s+([A-Za-z]+)\s+to\s+(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})', clean_str)
        if match_split_month:
            start_day, start_month, end_day, end_month, year_str = match_split_month.groups()
            year = int(year_str)
            dt_start = datetime.strptime(f"{start_day} {start_month} {year}", "%d %B %Y").date()
            dt_end = datetime.strptime(f"{end_day} {end_month} {year}", "%d %B %Y").date()
            return dt_start, dt_end
    except Exception:
        pass
    return None, None

# --- Data Parsing Engine ---
def extract_schedule_from_html(html_source):
    soup = BeautifulSoup(html_source, "html.parser")
    days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
    schedule = {day: [] for day in days}
    
    # Extract date range banner text if available
    date_label = "Unknown Dates"
    date_tag = soup.find("a", title="Pick a date")
    if date_tag:
        date_label = date_tag.get_text(strip=True)
    
    for idx, day_name in enumerate(days):
        container = soup.find("div", class_=f"day-{idx}")
        if container:
            for item in container.find_all("div", class_="item"):
                times = item.find("span", class_="times").get_text(strip=True) if item.find("span", class_="times") else ""
                title = item.find("span", class_="title").get_text(strip=True) if item.find("span", class_="title") else ""
                room = item.find("span", class_="room").get_text(strip=True) if item.find("span", class_="room") else ""
                
                schedule[day_name].append({
                    "time": times, "title": title, "room": room
                })
                
    return {"date_range": date_label, "days": schedule}

def extract_week_id(html_source):
    soup = BeautifulSoup(html_source, "html.parser")
    mobile_div = soup.find("div", class_=lambda x: x and "timetable-mobile" in x)
    if mobile_div and mobile_div.has_attr("data-week"):
        return int(mobile_div["data-week"])
        
    next_btn = soup.find("a", class_="next")
    if next_btn and "week=" in next_btn.get("href", ""):
        url_part = next_btn["href"].split("week=")[-1]
        return int(url_part) - 1
        
    return None

# --- Background Scraper Task ---
def run_scraper_task(status_callback, on_complete):
    status_callback("Launching Chrome...")
    options = Options()
    options.add_argument(f"--user-data-dir={PROFILE_DIR}")
    
    driver = webdriver.Chrome(options=options)
    all_weeks_data = {}
    
    try:
        driver.get("https://intranet.psc.ac.uk/timetable")
        status_callback("Checking session... Log in via Chrome if asked.")
        
        WebDriverWait(driver, 60).until(EC.url_contains("timetable"))
            
        status_callback("Waiting for timetable to render...")
        WebDriverWait(driver, 15).until(
            EC.presence_of_element_located((By.CLASS_NAME, "timetable-mobile"))
        )
        
        status_callback("Extracting base week ID...")
        base_html = driver.page_source
        current_week_id = extract_week_id(base_html)
        
        if not current_week_id:
            status_callback("Error: Could not find Week ID.")
            return

        # Check today's date against the initially loaded week to ensure alignment
        initial_parsed = extract_schedule_from_html(base_html)
        start_date, end_date = parse_date_range_string(initial_parsed["date_range"])
        
        target_base_id = current_week_id
        today = date.today()
        
        if start_date and end_date:
            if today > end_date:
                # Today is past this week, adjust base ID forward
                target_base_id += 1
            elif today < start_date:
                # Today is before this week, adjust base ID backward
                target_base_id -= 1

        # Fetch range of weeks around the current date
        for offset in range(-1, WEEKS_TO_FETCH - 1):
            target_week = target_base_id + offset
            status_callback(f"Fetching Week ID {target_week}...")
            
            driver.get(f"https://intranet.psc.ac.uk/timetable?week={target_week}")
            driver.implicitly_wait(2)
            
            week_html = driver.page_source
            parsed = extract_schedule_from_html(week_html)
            
            label = f"Week {target_week} ({parsed['date_range']})"
            all_weeks_data[label] = parsed["days"]
            
        with open(DATA_FILE, "w", encoding="utf-8") as f:
            json.dump(all_weeks_data, f, indent=4)
            
        status_callback("Sync complete! Data cached.")
        
    except Exception as err:
        status_callback(f"Sync failed: {str(err)}")
    finally:
        driver.quit()
        on_complete()

# --- GUI Application ---
class TimetableApp(ctk.CTk):
    def __init__(self):
        super().__init__()
        self.title("Peter Symonds Calendar Dashboard")
        self.geometry("1100x650")
        ctk.set_appearance_mode("dark")
        
        self.cached_data = self.load_data()

        # Header Frame
        self.header_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.header_frame.pack(pady=10, fill="x", padx=20)
        
        self.title_lbl = ctk.CTkLabel(self.header_frame, text="My College Timetable", font=("Arial", 24, "bold"))
        self.title_lbl.pack(side="left")

        # Week Selector Dropdown
        week_keys = list(self.cached_data.keys()) if self.cached_data else ["No Data"]
        self.week_selector = ctk.CTkOptionMenu(
            self.header_frame, 
            values=week_keys,
            command=self.render_calendar,
            width=280
        )
        self.week_selector.pack(side="right", padx=10)

        # Calendar Grid Frame
        self.calendar_frame = ctk.CTkFrame(self)
        self.calendar_frame.pack(fill="both", expand=True, padx=20, pady=10)
        
        for i in range(5):
            self.calendar_frame.grid_columnconfigure(i, weight=1)

        # Status & Controls
        self.control_frame = ctk.CTkFrame(self, fg_color="transparent")
        self.control_frame.pack(pady=10, fill="x", padx=20)
        
        self.status_label = ctk.CTkLabel(self.control_frame, text="Ready", font=("Arial", 12))
        self.status_label.pack(side="left")
        
        self.reset_button = ctk.CTkButton(self.control_frame, text="Reset Data", fg_color="#A31D1D", hover_color="#6D0D0D", command=self.clear_session)
        self.reset_button.pack(side="right", padx=5)
        
        self.sync_button = ctk.CTkButton(self.control_frame, text="Sync Latest Weeks", command=self.start_sync)
        self.sync_button.pack(side="right", padx=5)

        if week_keys[0] != "No Data":
            self.week_selector.set(week_keys[0])
            self.render_calendar(week_keys[0])
        else:
            self.render_calendar("No Data")

    def load_data(self):
        if os.path.exists(DATA_FILE):
            with open(DATA_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        return {}

    def set_status(self, msg):
        self.status_label.configure(text=msg)

    def render_calendar(self, selected_week):
        for widget in self.calendar_frame.winfo_children():
            widget.destroy()

        days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        week_data = self.cached_data.get(selected_week, {day: [] for day in days})

        for col_idx, day in enumerate(days):
            header = ctk.CTkLabel(self.calendar_frame, text=day, font=("Arial", 16, "bold"), fg_color="#333333", corner_radius=5)
            header.grid(row=0, column=col_idx, sticky="ew", padx=5, pady=5, ipady=5)
            
            col_scroll = ctk.CTkScrollableFrame(self.calendar_frame)
            col_scroll.grid(row=1, column=col_idx, sticky="nsew", padx=5, pady=5)
            self.calendar_frame.grid_rowconfigure(1, weight=1)
            
            classes = week_data.get(day, [])
            if not classes:
                ctk.CTkLabel(col_scroll, text="No classes", text_color="gray").pack(pady=20)
            else:
                for cls in classes:
                    card = ctk.CTkFrame(col_scroll, fg_color="#2b2b2b", corner_radius=8)
                    card.pack(fill="x", pady=5)
                    
                    ctk.CTkLabel(card, text=cls['title'], font=("Arial", 12, "bold"), wraplength=140).pack(pady=(5,0))
                    ctk.CTkLabel(card, text=cls['time'], font=("Arial", 11)).pack()
                    ctk.CTkLabel(card, text=cls['room'], font=("Arial", 11), text_color="#00a8ff").pack(pady=(0,5))

    def start_sync(self):
        self.sync_button.configure(state="disabled")
        
        def finish():
            self.sync_button.configure(state="normal")
            self.cached_data = self.load_data()
            if self.cached_data:
                weeks = list(self.cached_data.keys())
                self.week_selector.configure(values=weeks)
                self.week_selector.set(weeks[0])
                self.render_calendar(weeks[0])
                
        threading.Thread(target=run_scraper_task, args=(self.set_status, finish), daemon=True).start()

    def clear_session(self):
        if os.path.exists(PROFILE_DIR):
            shutil.rmtree(PROFILE_DIR)
        if os.path.exists(DATA_FILE):
            os.remove(DATA_FILE)
            
        self.cached_data = {}
        self.week_selector.configure(values=["No Data"])
        self.week_selector.set("No Data")
        self.render_calendar("No Data")
        self.set_status("Session deleted.")

if __name__ == "__main__":
    app = TimetableApp()
    app.mainloop()
