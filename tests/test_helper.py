"""Run: python3 -I -B -m unittest discover tests   (from the plugin dir)"""
import datetime as dt
import http.server
import json
import os
import sys
import tempfile
import threading
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import tidepool_helper as h  # noqa: E402


def ics_for(day, summary="Standup", start="090000", end="093000"):
    d = day.strftime("%Y%m%d")
    return ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:%s@t\r\nSUMMARY:%s\r\n"
            "DTSTART:%sT%s\r\nDTEND:%sT%s\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n") % (summary, summary, d, start, d, end)


class Serve(http.server.BaseHTTPRequestHandler):
    body = b""

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "https://10.0.0.1/x.ics")
            self.end_headers()
        elif self.path == "/denied":
            self.send_response(403)
            self.end_headers()
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(Serve.body)


class HelperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["TIDEPOOL_STATE_DIR"] = os.path.join(self.tmp.name, "state")
        os.environ["TIDEPOOL_CONFIG_DIR"] = os.path.join(self.tmp.name, "config")
        self.today = dt.date.today()

    def tearDown(self):
        self.tmp.cleanup()

    def test_source_id_stable_and_kind_sensitive(self):
        a = h.source_id({"kind": "ics-url", "url": "https://x/y.ics"})
        self.assertEqual(len(a), 16)
        self.assertEqual(a, h.source_id({"kind": "ics-url", "url": "https://x/y.ics", "color": "#fff"}))
        self.assertNotEqual(a, h.source_id({"kind": "caldav", "url": "https://x/y.ics"}))

    def test_check_url_rules(self):
        self.assertEqual(h.check_url("webcal://localhost/a.ics", loopback_ok=True), "https://localhost/a.ics")
        for bad in ("ftp://x/a", "http://example.com/a.ics", "https://u:p@example.com/a", "file:///etc/passwd"):
            with self.assertRaises(h.HelperError) as c:
                h.check_url(bad)
            self.assertEqual(c.exception.code, "bad-url")
        with self.assertRaises(h.HelperError) as c:
            h.check_url("https://192.168.1.5/a.ics")
        self.assertEqual(c.exception.code, "private-address")
        with self.assertRaises(h.HelperError):
            h.check_url("https://100.64.1.1/a.ics")  # CGNAT / Tailscale
        self.assertEqual(h.check_url("https://192.168.1.5/a.ics", allow_local=True), "https://192.168.1.5/a.ics")

    def test_file_and_vdir_sync(self):
        f = os.path.join(self.tmp.name, "one.ics")
        open(f, "w").write(ics_for(self.today, "FileEv"))
        d = os.path.join(self.tmp.name, "dir")
        os.mkdir(d)
        open(os.path.join(d, "a.ics"), "w").write(ics_for(self.today, "DirEv", "100000", "110000"))
        r = h.sync({"sources": [{"kind": "file", "path": f, "color": "#112233"},
                                {"kind": "vdir", "path": d},
                                {"kind": "file", "path": "/nonexistent.ics"}]})
        titles = sorted(i["title"] for i in r["items"])
        self.assertEqual(titles, ["DirEv", "FileEv"])
        self.assertEqual(r["items"][0]["color"] if r["items"][0]["title"] == "FileEv" else "#112233", "#112233")
        self.assertEqual(list(r["errors"].values()), ["read-error"])
        ev = [i for i in r["items"] if i["title"] == "FileEv"][0]
        self.assertEqual(ev["start"], self.today.isoformat() + "T09:00:00")
        self.assertFalse(ev["allDay"])
        # the sync result is cached for instant startup
        self.assertEqual(len(h.read_json(os.path.join(h.state_dir(), "cache.json"), {})["items"]), 2)

    def test_ics_url_over_localhost(self):
        Serve.body = ics_for(self.today, "Remote").encode()
        srv = http.server.HTTPServer(("127.0.0.1", 0), Serve)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        base = "http://127.0.0.1:%d" % srv.server_port
        try:
            r = h.sync({"sources": [{"kind": "ics-url", "url": base + "/a.ics"},
                                    {"kind": "ics-url", "url": base + "/redirect"},
                                    {"kind": "ics-url", "url": base + "/denied"}]})
        finally:
            srv.shutdown()
        self.assertEqual([i["title"] for i in r["items"]], ["Remote"])
        self.assertEqual(sorted(r["errors"].values()), ["auth-error", "redirect-refused"])

    def test_disabled_and_unknown_kinds_skipped(self):
        r = h.sync({"sources": [{"kind": "nope"}, {"kind": "file", "path": "/x", "enabled": False}]})
        self.assertEqual(r["items"], [])
        self.assertEqual(r["errors"], {})

    def test_settings_roundtrip_and_cleaning(self):
        self.assertEqual(h.settings_get()["values"]["calendarRefresh"], 15)
        src = {"kind": "ics-url", "url": " https://x.example/a.ics ", "color": "#aabbcc", "junk": "x", "enabled": 1}
        bad = {"kind": "telepathy", "url": "x"}
        out = h.settings_set({"values": {"calendarSources": [src, bad], "calendarRefresh": 1, "nonsense": 1}})["values"]
        self.assertEqual(len(out["calendarSources"]), 1)
        self.assertEqual(out["calendarSources"][0], {"kind": "ics-url", "url": "https://x.example/a.ics", "color": "#aabbcc", "enabled": True})
        self.assertEqual(out["calendarRefresh"], 5)
        self.assertNotIn("nonsense", out)
        self.assertEqual(h.settings_get()["ids"], [h.source_id(out["calendarSources"][0])])
        self.assertEqual(oct(os.stat(h.settings_path()).st_mode & 0o777), "0o600")
        # selection keeps only ids that exist
        sid = h.source_id(out["calendarSources"][0])
        out = h.settings_set({"values": {"calendarSelection": [sid, "ghost"]}})["values"]
        self.assertEqual(out["calendarSelection"], [sid])
        # a patch that does not mention sources leaves them alone
        self.assertEqual(len(h.settings_set({"values": {"hideAllDayEvents": True}})["values"]["calendarSources"]), 1)

    def test_agenda_days(self):
        self.assertEqual(h.settings_get()["values"]["agendaDays"], 1)
        self.assertEqual(h.settings_set({"values": {"agendaDays": 7}})["values"]["agendaDays"], 7)
        self.assertEqual(h.settings_set({"values": {"agendaDays": 5}})["values"]["agendaDays"], 1)
        self.assertEqual(h.settings_set({"values": {"agendaDays": "x"}})["values"]["agendaDays"], 1)

    def test_settings_cap_sources(self):
        many = [{"kind": "file", "path": "/p/%d.ics" % i} for i in range(50)]
        self.assertEqual(len(h.settings_set({"values": {"calendarSources": many}})["values"]["calendarSources"]), h.MAX_SOURCES)

    def test_import_nookisle(self):
        nk = os.path.join(self.tmp.name, "nk.json")
        import json
        json.dump({"version": 1, "values": {"calendarSources": [
            {"kind": "caldav", "url": "https://dav.example/", "user": "me"}, {"kind": "file", "path": "/a.ics"}]}}, open(nk, "w"))
        r = h.import_nookisle({"path": nk})
        self.assertEqual(r["added"], 2)
        self.assertEqual(h.import_nookisle({"path": nk})["added"], 0)  # idempotent
        with self.assertRaises(h.HelperError):
            h.import_nookisle({"path": os.path.join(self.tmp.name, "missing.json")})

    def test_search_zones(self):
        names = lambda q: [z["zone"] for z in h.search_zones({"query": q})["zones"]]
        self.assertEqual(names("tokyo")[0], "Asia/Tokyo")
        self.assertEqual(names("New York")[0], "America/New_York")
        self.assertIn("Europe/London", names("lond"))
        self.assertEqual(names("t"), [])
        self.assertEqual(names("zzzzqq"), [])
        self.assertTrue(all(not n.startswith("Etc/") for n in names("gmt")))
        self.assertLessEqual(len(names("a" * 2)), 8)

    def test_meeting_url(self):
        f = h.ics.find_meeting_url
        self.assertEqual(f("", "Room 4", "Join: https://zoom.us/j/123456?pwd=abc. See you"), "https://zoom.us/j/123456?pwd=abc")
        self.assertEqual(f("https://meet.google.com/abc-defg-hij", "", ""), "https://meet.google.com/abc-defg-hij")
        self.assertEqual(f("", "", "https://us02web.zoom.us/j/9"), "https://us02web.zoom.us/j/9")
        self.assertEqual(f("", "", "Teams: https://teams.microsoft.com/l/meetup-join/abc"), "https://teams.microsoft.com/l/meetup-join/abc")
        self.assertEqual(f("", "https://example.com/venue", "see https://docs.google.com/x"), "")
        self.assertEqual(f("", "https://notzoom.us.evil.com/j/1", ""), "")
        self.assertEqual(f(None, None, None), "")

    def test_event_details_parsed(self):
        d = self.today.strftime("%Y%m%d")
        text = ("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nSUMMARY:Sync\r\nDTSTART:%sT100000\r\nDTEND:%sT103000\r\n"
                "LOCATION:Room 4\r\nDESCRIPTION:Agenda\\nJoin https://zoom.us/j/5\r\nORGANIZER;CN=Ana:mailto:ana@x.org\r\n"
                "ATTENDEE;CN=Bo:mailto:bo@x.org\r\nATTENDEE:mailto:cy@x.org\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n") % (d, d)
        ev = h.ics.parse_events(text, self.today, self.today)[0]
        self.assertEqual(ev["meetingUrl"], "https://zoom.us/j/5")
        self.assertEqual(ev["organizer"], "Ana")
        self.assertEqual(ev["attendees"], ["Bo", "cy@x.org"])
        self.assertEqual(ev["attendeeCount"], 2)
        self.assertIn("Agenda", ev["description"])

    def test_notify_due_once(self):
        sent = []
        h.send_notification = lambda title, body, urgency="normal": (sent.append((title, body)) or True)
        soon = (dt.datetime.now() + dt.timedelta(minutes=4)).strftime("%Y-%m-%dT%H:%M:%S")
        far = (dt.datetime.now() + dt.timedelta(hours=5)).strftime("%Y-%m-%dT%H:%M:%S")
        items = [{"key": "k1", "title": "Standup", "start": soon, "location": "Room 4", "url": "https://zoom.us/j/1"},
                 {"key": "k2", "title": "Later", "start": far}]
        self.assertEqual(h.notify_due({"items": items})["sent"], 1)
        self.assertEqual(sent[0][0], "Standup")
        self.assertIn("Room 4", sent[0][1])
        self.assertIn("Join: https://zoom.us/j/1", sent[0][1])
        self.assertEqual(h.notify_due({"items": items})["sent"], 0)   # not twice
        self.assertEqual(len(sent), 1)

    def test_ancestors_walk_up_and_stop(self):
        tree = {900: 800, 800: 700, 700: 1, 5: 5}
        self.assertEqual(h.ancestors(900, tree.get), [900, 800, 700])
        self.assertEqual(h.ancestors(5, tree.get), [5])            # a loop does not hang
        self.assertEqual(h.ancestors(1, tree.get), [])
        self.assertEqual(h.ancestors(900, lambda p: p + 1, limit=4), [900, 901, 902, 903])
        self.assertGreater(len(h.ancestors(os.getpid())), 1)       # the real /proc works

    def test_pick_window_prefers_the_owning_process(self):
        win = lambda addr, pid, cls, title, **k: dict(address=addr, pid=pid, **{"class": cls}, title=title, mapped=True, **k)
        clients = [win("0x1", 100, "ghostty", "~"), win("0x2", 200, "ghostty", "Burning Love"), win("0x3", 300, "plezy", "Plezy")]
        # a TUI (pid 250) runs inside terminal 200: found through its parent
        self.assertEqual(h.pick_window(clients, [250, 200, 1], {})["address"], "0x2")
        self.assertEqual(h.pick_window(clients, [300], {})["address"], "0x3")
        # one process owning several windows: the track title decides
        shared = [win("0xa", 7, "ghostty", "~"), win("0xb", 7, "ghostty", "Song Name - Artist")]
        self.assertEqual(h.pick_window(shared, [8, 7], {"title": "Song Name"})["address"], "0xb")
        # hidden / unmapped windows are not used
        self.assertIsNone(h.pick_window([dict(win("0x9", 5, "x", "x"), mapped=False)], [5], {}))

    def test_pick_window_falls_back_to_class_and_title(self):
        clients = [dict(address="0x1", pid=1, title="Home", mapped=True, **{"class": "zen"}),
                   dict(address="0x2", pid=2, title="Mix - YouTube", mapped=True, **{"class": "chromium"})]
        self.assertEqual(h.pick_window(clients, [], {"desktopEntry": "chromium"})["address"], "0x2")
        self.assertEqual(h.pick_window(clients, [], {"title": "mix - youtube"})["address"], "0x2")
        self.assertEqual(h.pick_window(clients, [], {"identity": "Zen"})["address"], "0x1")
        self.assertIsNone(h.pick_window(clients, [], {"title": "nothing like it"}))
        self.assertIsNone(h.pick_window(clients, [], {}))

    def test_focus_app_dispatches_only_a_valid_address(self):
        calls = []
        def fake(cmd, timeout=4):
            calls.append(cmd)
            class R: pass
            r = R(); r.returncode = 0
            if cmd[0] == "busctl": r.stdout = "u 300\n"
            elif cmd[:2] == ["hyprctl", "clients"]: r.stdout = json.dumps([{"address": "0x3", "pid": 300, "class": "plezy", "title": "Plezy", "mapped": True}])
            else: r.stdout = "ok"
            return r
        orig = h._run; h._run = fake
        try:
            out = h.focus_app({"dbusName": "org.mpris.MediaPlayer2.plezy"})
            self.assertTrue(out["ok"]); self.assertEqual(out["title"], "Plezy")
            self.assertIn('address:0x3', calls[-1][-1])
            calls.clear()
            h.focus_app({"dbusName": "evil; rm -rf /"})                 # never reaches busctl
            self.assertFalse(any(c[0] == "busctl" for c in calls))
        finally:
            h._run = orig

    def test_loopback_only_when_the_request_started_there(self):
        # a public server must not be able to redirect us to a service on this machine
        for url in ("https://localhost/x", "http://127.0.0.1:8080/x", "http://[::1]/x"):
            with self.assertRaises(h.HelperError, msg=url) as c:
                h.check_url(url)
            self.assertIn(c.exception.code, ("private-address", "bad-url"))
        self.assertEqual(h.check_url("http://127.0.0.1:8080/x", loopback_ok=True), "http://127.0.0.1:8080/x")
        self.assertEqual(h.check_url("https://10.1.2.3/x", allow_local=True), "https://10.1.2.3/x")
        with self.assertRaises(h.HelperError):                       # plain http stays loopback-only
            h.check_url("http://10.1.2.3/x", allow_local=True)

    def test_connection_refuses_a_private_address_even_if_the_name_looked_public(self):
        # DNS rebinding: the name passed the check, but now resolves to the LAN
        real = h.socket.getaddrinfo
        h.socket.getaddrinfo = lambda host, port, **k: [(h.socket.AF_INET, h.socket.SOCK_STREAM, 6, "", ("10.0.0.5", port))]
        try:
            h._POLICY.update(allow_local=False, loopback_ok=False)
            with self.assertRaises(h.HelperError) as c:
                h._pinned_connection(("calendar.example.com", 443), 2)
            self.assertEqual(c.exception.code, "private-address")
        finally:
            h.socket.getaddrinfo = real

    def test_login_is_not_forwarded_to_another_host(self):
        seen = {}

        class Target(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def do_GET(self):
                seen["auth"] = self.headers.get("Authorization")
                self.send_response(200); self.end_headers(); self.wfile.write(b"BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n")

        target = http.server.HTTPServer(("127.0.0.1", 0), Target)
        port = target.server_port

        class Bounce(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a): pass
            def do_GET(self):
                self.send_response(302)
                self.send_header("Location", "http://localhost:%d/cal.ics" % port)   # same machine, different host name
                self.end_headers()

        bounce = http.server.HTTPServer(("127.0.0.1", 0), Bounce)
        for srv in (target, bounce):
            threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            status, _, body = h.http_request("GET", "http://127.0.0.1:%d/start" % bounce.server_port,
                                             {"Authorization": "Basic c2VjcmV0"})
        finally:
            for srv in (target, bounce):
                srv.shutdown(); srv.server_close()
        self.assertEqual(status, 200)
        self.assertIsNone(seen["auth"])

    def test_notification_title_cannot_become_an_option(self):
        got = []
        class R: returncode = 0
        orig = h.subprocess.run
        h.subprocess.run = lambda cmd, **k: (got.append(cmd) or R())
        try:
            h.send_notification("-u critical --help", "body")
        finally:
            h.subprocess.run = orig
        cmd = got[0]
        self.assertIn("--", cmd)
        self.assertLess(cmd.index("--"), cmd.index("-u critical --help"))

    def test_concurrent_setting_changes_are_not_lost(self):
        import subprocess
        procs = []
        env = dict(os.environ, TIDEPOOL_CONFIG_DIR=os.environ["TIDEPOOL_CONFIG_DIR"], TIDEPOOL_STATE_DIR=os.environ["TIDEPOOL_STATE_DIR"])
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "bin", "tidepool-helper")
        patches = [{"hideAllDayEvents": True}, {"showFullEventTitles": True}, {"agendaDays": 7}, {"autoScrollToNextEvent": False}]
        for patch in patches:
            p = subprocess.Popen([sys.executable, "-I", "-B", script, "settings-set"], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, env=env)
            p.stdin.write(json.dumps({"values": patch}).encode()); p.stdin.close()
            procs.append(p)
        for p in procs:
            p.wait(timeout=20)
        v = h.settings_get()["values"]
        self.assertTrue(v["hideAllDayEvents"] and v["showFullEventTitles"] and v["agendaDays"] == 7 and v["autoScrollToNextEvent"] is False)

    def _rrule_count(self, rrule, years_ago, days=30):
        start = (self.today - dt.timedelta(days=365 * years_ago)).strftime("%Y%m%d")
        text = ("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:r\r\nSUMMARY:R\r\nDTSTART;VALUE=DATE:%s\r\nRRULE:%s\r\n"
                "END:VEVENT\r\nEND:VCALENDAR\r\n") % (start, rrule)
        return len(h.ics.parse_events(text, self.today, self.today + dt.timedelta(days=days)))

    def test_old_recurring_events_still_show(self):
        # these used to hit the occurrence cap while walking from the start and vanish
        self.assertEqual(self._rrule_count("FREQ=DAILY", 7), 31)
        self.assertEqual(self._rrule_count("FREQ=DAILY;INTERVAL=3", 9), 11)
        self.assertIn(self._rrule_count("FREQ=WEEKLY", 15), (4, 5))
        self.assertEqual(self._rrule_count("FREQ=MONTHLY", 20), 1)
        self.assertEqual(self._rrule_count("FREQ=YEARLY", 30), 1)

    def test_count_still_ends_a_recurrence(self):
        self.assertEqual(self._rrule_count("FREQ=DAILY;COUNT=5", 2), 0)
        self.assertEqual(self._rrule_count("FREQ=DAILY;COUNT=5", 0), 5)

    def test_a_malformed_event_does_not_sink_the_feed(self):
        d = self.today.strftime("%Y%m%d")
        text = ("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nSUMMARY:Odd\r\nDTSTART;VALUE=DATE:%s\r\nRRULE:FREQ=MONTHLY;BYMONTHDAY=x;INTERVAL=y\r\nEND:VEVENT\r\n"
                "BEGIN:VEVENT\r\nUID:b\r\nSUMMARY:Fine\r\nDTSTART;VALUE=DATE:%s\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n") % (d, d)
        self.assertIn("Fine", [e["title"] for e in h.ics.parse_events(text, self.today, self.today)])

    def test_windows_time_zone_names_are_understood(self):
        d = self.today.strftime("%Y%m%d")
        mk = lambda tz: ("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:w\r\nSUMMARY:W\r\nDTSTART;TZID=%s:%sT130000\r\nDTEND;TZID=%s:%sT140000\r\n"
                         "END:VEVENT\r\nEND:VCALENDAR\r\n") % (tz, d, tz, d)
        win = h.ics.parse_events(mk("Eastern Standard Time"), self.today, self.today)[0]["start"]
        iana = h.ics.parse_events(mk("America/New_York"), self.today, self.today)[0]["start"]
        self.assertEqual(win, iana)                       # same instant, whatever zone the test runs in
        self.assertEqual(win.utcoffset() if win.tzinfo else None, None)   # still a naive local time

    def test_zones(self):
        z = h.zones({"zones": ["UTC", "Asia/Tokyo", "Not/AZone"]})["zones"]
        self.assertEqual(z["UTC"]["offsetMin"], 0)
        self.assertEqual(z["Asia/Tokyo"]["offsetMin"], 540)
        self.assertIn("error", z["Not/AZone"])

    def test_place_label(self):
        self.assertEqual(h.place_label({"name": "Austin", "admin1": "Texas", "country_code": "US"}), "Austin, Texas, US")
        self.assertEqual(h.place_label({"name": "Singapore", "admin1": "Singapore", "country_code": "SG"}), "Singapore, SG")
        self.assertEqual(h.place_label({"name": "X"}), "X")

    def test_search_city_short_query_makes_no_request(self):
        self.assertEqual(h.search_city({"query": " a "}), {"places": []})
        self.assertEqual(h.search_city({}), {"places": []})

    def test_known_place_from_dropdown(self):
        p = h.known_place({"city": "Austin, Texas, US", "lat": 30.27, "lon": -97.74})
        self.assertEqual((p["name"], p["region"], p["country"]), ("Austin", "Texas", "US"))
        p = h.known_place({"city": "Singapore, SG", "lat": "1.29", "lon": "103.85"})
        self.assertEqual((p["name"], p["region"], p["country"]), ("Singapore", "", "SG"))
        self.assertIsNone(h.known_place({"city": "x", "lat": 95, "lon": 0}))
        self.assertIsNone(h.known_place({"city": "x", "lat": "", "lon": ""}))
        self.assertIsNone(h.known_place({"city": "x"}))

    def test_weather_needs_city(self):
        with self.assertRaises(h.HelperError) as c:
            h.weather({"city": " "})
        self.assertEqual(c.exception.code, "no-city")


if __name__ == "__main__":
    unittest.main()
