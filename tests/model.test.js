// Run: node tests/model.test.js
const M = require("../Model.js");
let failed = 0;
function ok(name, cond) { console.log((cond ? "PASS " : "FAIL ") + name); if (!cond) failed++; }

const at = (d, h, m) => new Date(2026, 9, d, h, m, 0);
const iso = (d, h, m) => `2026-10-${String(d).padStart(2, "0")}T${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:00`;
const ev = (title, d, sh, sm, eh, em, extra) => Object.assign({ sourceId: "a", title, allDay: false, start: iso(d, sh, sm), end: iso(d, eh, em), color: "#abc" }, extra || {});
const now = at(11, 9, 0);

ok("parseColors", JSON.stringify(M.parseColors('mode = "dark"\naccent = "#86C432"\n red="#ee8075"\nbad = "x"')) === '{"accent":"#86c432","red":"#ee8075"}');
ok("glyphs", M.glyph("timer").codePointAt(0) === 0xF051B && M.glyph("nope") === "" && Object.keys(M.GLYPH).every(k => M.glyph(k).length === 2));
ok("coordinates kept", M.resolveSettings({ weatherLat: 30.27, weatherLon: "-97.74" }).weatherLon === -97.74);
ok("bad or partial coordinates dropped", M.resolveSettings({ weatherLat: 95, weatherLon: 0 }).weatherLat === null && M.resolveSettings({ weatherLat: 10 }).weatherLon === null && M.resolveSettings({ weatherLat: "", weatherLon: "" }).weatherLat === null);
ok("loopNext cycles", M.loopNext("None") === "Playlist" && M.loopNext("Playlist") === "Track" && M.loopNext("Track") === "None" && M.loopNext("x") === "None");
ok("parseBars", M.parseBars("0;50;100;", 4).join() === "0,50,100,0" && M.parseBars("5;999;-3;x;", 3).join() === "5,100,0" && M.parseBars("", 2).join() === "0,0");
ok("media glyphs", ["shuffle", "repeat", "repeat-once", "volume", "volume-off"].every(k => M.glyph(k).length === 2));
// settings
const s = M.resolveSettings({ clockMode: "bogus", rotateSeconds: 999, soonMinutes: 0, units: "x", timerPresets: "5, 15, nope, 0, 5000, 25", worldClocks: "Asia/Tokyo; ../etc, Europe/London" });
ok("clock mode falls back", s.clockMode === "time");
ok("extras default", M.resolveSettings({}).showEvent && M.resolveSettings({}).showTimer && !M.resolveSettings({}).showMedia && !M.resolveSettings({}).showWeather && M.resolveSettings({}).extrasShown === 4);
ok("toggles accept false/'false'", !M.resolveSettings({ showEvent: false }).showEvent && !M.resolveSettings({ showTimer: "false" }).showTimer);
ok("legacy face clock", !M.resolveSettings({ face: "clock" }).showEvent && !M.resolveSettings({ face: "clock" }).showTimer);
ok("old showMusic name still read", M.resolveSettings({ showMusic: true }).showMedia === true && M.resolveSettings({ showMusic: true, showMedia: false }).showMedia === false);
ok("legacy face rotate", M.resolveSettings({ face: "rotate" }).extrasShown === 1 && M.resolveSettings({ face: "rotate" }).showMedia);
ok("legacy rotateExtras", M.resolveSettings({ rotateExtras: true }).extrasShown === 1 && M.resolveSettings({ rotateExtras: false }).extrasShown === 4 && M.resolveSettings({ rotateExtras: true, extrasShown: 2 }).extrasShown === 2);
ok("media options default off", M.resolveSettings({}).showMediaStatus === false && M.resolveSettings({}).miniVisualizer === false);
ok("media options on", M.resolveSettings({ showMediaStatus: true, miniVisualizer: "true" }).showMediaStatus === true && M.resolveSettings({ miniVisualizer: "true" }).miniVisualizer === true && M.resolveSettings({ miniVisualizer: "no" }).miniVisualizer === false);
ok("visualizer style", M.resolveSettings({}).visualizerStyle === "bars" && M.VIZ_STYLES.length === 6 && M.VIZ_STYLES.every(v => M.resolveSettings({ visualizerStyle: v }).visualizerStyle === v) && M.resolveSettings({ visualizerStyle: "neon" }).visualizerStyle === "bars");
ok("viz labels", M.VIZ_STYLES.every(v => M.vizLabel(v).length > 0 && M.vizLabel(v)[0] === M.vizLabel(v)[0].toUpperCase()) && M.vizLabel("fire") === "Fire" && M.vizLabel("nope") === "Bars");
ok("viz step wraps both ways", M.vizStep("bars", 1) === "mirror" && M.vizStep("bars", -1) === "fire" && M.vizStep("fire", 1) === "bars" && M.vizStep("dots", -1) === "mirror" && M.vizStep("bars", 6) === "bars" && M.vizStep("bars", -7) === "fire");
ok("viz step from an unknown style starts at the first", M.vizStep("nope", 1) === "mirror" && M.vizStep(undefined, 0) === "bars");
const cg = M.cellGrid(900, 120, 48);
ok("cell grid is square", cg.cols === 48 && cg.pitch === 18.75 && cg.rows === 6 && cg.size < cg.pitch && M.cellGrid(10, 0, 0).rows === 1);
ok("noise is deterministic and in range", M.noise(3, 4, 5) === M.noise(3, 4, 5) && M.noise(3, 4, 5) !== M.noise(3, 4, 6) && (() => { for (let i = 0; i < 2000; ++i) { const n = M.noise(i, i * 7, i * 13); if (!(n >= 0 && n < 1)) return false } return true })());
ok("noise is spread out", (() => { let lo = 0, hi = 0; for (let i = 0; i < 4000; ++i) { M.noise(i, 1, 2) < 0.5 ? lo++ : hi++ } return lo > 1700 && hi > 1700 })());
ok("fire height follows the level and flicker", M.fireHeight(1, 6, 0.5) === 6 && M.fireHeight(0, 6, 1) === 0 && M.fireHeight(0.5, 6, 1) > M.fireHeight(0.5, 6, 0) && M.fireHeight(9, 6, 0.5) === 6 && M.fireHeight(1, 6, 1) === 6);
ok("fire state: the base is solid whatever the noise", M.fireState(5, 0, 0.999) === 0 && M.fireState(5, 1, 0.999) === 0.2 && M.fireState(5, 2, 0.999) === 0.4);
ok("fire state: higher cells dissolve more", (() => { const lit = (row) => { let n = 0; for (let i = 0; i < 1000; ++i) if (M.fireState(8, row, i / 1000) >= 0) n++; return n }; return lit(3) > lit(5) && lit(5) > lit(7) && lit(7) > 0 && lit(7) < 300 })());
ok("fire state: lit cells report how far up they are", M.fireState(8, 4, 0) === 0.5 && M.fireState(8, 7, 0) === 0.875);
ok("fire state: sparks above, nothing far above or without a flame", M.fireState(3, 4, 0.99) === 1.5 && M.fireState(3, 4, 0.5) === -1 && M.fireState(3, 9, 0.99) === -1 && M.fireState(0, 1, 0.99) === -1 && M.fireState(0.3, 0, 0.5) === -1);
const fh = (t) => M.fireHsl(t, 0.25, 0.6, 0.5);
ok("fire colours: hot base, accent, neighbours, fading tip", Math.abs(fh(0)[0] - 0.21) < 1e-9 && fh(0)[2] > fh(0.3)[2] && Math.abs(fh(0.3)[0] - 0.25) < 1e-9 && Math.abs(fh(0.65)[0] - 0.32) < 1e-9 && Math.abs(fh(1)[0] - 0.38) < 1e-9 && fh(1)[3] < 0.35 && fh(0.65)[3] === 1);
ok("fire colours: hue wraps, spark is dimmer, all in range", (() => { const w = M.fireHsl(1, 0.95, 0.6, 0.5); const sp = M.fireHsl(1.5, 0.25, 0.6, 0.5); for (let t = -0.5; t <= 1.6; t += 0.05) for (const h of [0, 0.5, 0.99]) { const c = M.fireHsl(t, h, 1, 0.9); if (c.some(x => !(x >= 0 && x <= 1))) return false } return w[0] >= 0 && w[0] < 1 && Math.abs(sp[3] - fh(1)[3] * 0.6) < 1e-9 })());
const dg = M.dotGrid(900, 120, 48);
ok("dot grid: hex packing", dg.cols === 48 && Math.abs(dg.pitchX - 18.75) < 1e-9 && Math.abs(dg.pitchY - 18.75 * 0.866) < 1e-9 && dg.rows === Math.floor(120 / (18.75 * 0.866)) && dg.size < dg.pitchX);
ok("dot grid: tiny and degenerate boxes", M.dotGrid(22, 12, 8).rows >= 4 && M.dotGrid(10, 0, 4).rows === 1 && M.dotGrid(0, 0, 0).cols === 1);
ok("dot level: loud bands light more rows", M.dotLevel(1, 0, 5) === 1 && M.dotLevel(1, 4, 5) === 1 && M.dotLevel(0, 0, 5) === 0 && M.dotLevel(0.5, 0, 4) === 1 && M.dotLevel(0.5, 2, 4) === 0);
ok("dot level: the top row grows partway", Math.abs(M.dotLevel(0.3, 1, 5) - 0.5) < 1e-9 && Math.abs(M.dotLevel(0.1, 0, 5) - 0.5) < 1e-9);
ok("dot level: clamps bad input", M.dotLevel(9, 0, 5) === 1 && M.dotLevel(-3, 4, 5) === 0);
ok("dot scale", M.dotScale(0) === 0.18 && M.dotScale(1) === 1 && M.dotScale(0.5) > M.dotScale(0.2));
const wp = M.wavePath([0, 50, 100, 20], 90, 40, false);
ok("wave path: one curve per gap", wp.startsWith("M0 40") && (wp.match(/C/g) || []).length === 3 && !wp.includes("Z"));
const nums = (wavePathStr) => (wavePathStr.match(/-?\d+(\.\d+)?/g) || []).map(Number);
const wild = M.wavePath([0, 100, 0, 100, 0, 100, 0], 60, 30, true);
ok("wave path stays inside the box", (() => { const n = nums(wild); const xs = n.filter((_, i) => i % 2 === 0), ys = n.filter((_, i) => i % 2 === 1); return xs.every(v => v >= 0 && v <= 60) && ys.every(v => v >= 0 && v <= 30) })());
ok("closed wave ends on the baseline", /L60 30 L0 30 Z$/.test(wild));
ok("wave path clamps bad input", /^M0 40/.test(M.wavePath([-50, 500, "x"], 20, 40, false)) && !/NaN/.test(M.wavePath([NaN, undefined, null], 20, 40, true)));
ok("wave path with nothing is a flat baseline", M.wavePath([], 50, 10, false) === "M0 10 L50 10" && M.wavePath(null, 50, 10, true).endsWith("Z"));
ok("extra style", M.resolveSettings({}).extraStyle === "plain" && M.resolveSettings({ extraStyle: "border" }).extraStyle === "border" && M.resolveSettings({ extraStyle: "button" }).extraStyle === "button" && M.resolveSettings({ extraStyle: "neon" }).extraStyle === "plain");
ok("extrasShown clamps", M.resolveSettings({ extrasShown: 9 }).extrasShown === 4 && M.resolveSettings({ extrasShown: -1 }).extrasShown === 0 && M.resolveSettings({ extrasShown: 0 }).extrasShown === 0);
const ex = ["event", "timer", "media", "weather"];
ok("page count", M.extraPageCount(4, 1) === 4 && M.extraPageCount(4, 2) === 2 && M.extraPageCount(3, 2) === 2 && M.extraPageCount(4, 4) === 1 && M.extraPageCount(2, 4) === 1 && M.extraPageCount(4, 0) === 0 && M.extraPageCount(0, 2) === 0);
ok("pages", M.extraPage(ex, 1, 1).join() === "timer" && M.extraPage(ex, 2, 1).join() === "media,weather" && M.extraPage(ex, 2, 2).join() === "event,timer" && M.extraPage(ex, 3, 1).join() === "weather" && M.extraPage(ex, 0, 0).length === 0 && M.extraPage(ex, 4, 5).join() === ex.join());
ok("legacy fills only unset", M.resolveSettings({ face: "clock", showEvent: true }).showEvent === true);
ok("legacy ignored when clockMode set", M.resolveSettings({ face: "clock", clockMode: "both" }).showEvent);
ok("numbers clamp", s.rotateSeconds === 60 && s.soonMinutes === 1);
ok("horizon + tide defaults", M.resolveSettings({}).chipHorizonHours === 12 && M.resolveSettings({ tideLine: "false" }).tideLine === false);
ok("units default", s.units === "metric");
ok("presets parsed", s.timerPresets.join() === "5,15,25");
ok("zones validated", s.worldClocks.join() === "Asia/Tokyo,Europe/London");
ok("empty presets default", M.parsePresets("").join() === "5,15,25,45");
ok("peekOnHover string false", M.resolveSettings({ peekOnHover: "false" }).peekOnHover === false);

// day rows
const items = [ev("Late", 11, 15, 0, 16, 0), ev("Standup", 11, 9, 30, 10, 0), ev("Hidden", 11, 11, 0, 12, 0, { sourceId: "b" }),
  { sourceId: "a", title: "Holiday", allDay: true, start: "2026-10-11", end: "2026-10-12" },
  ev("Tomorrow", 12, 10, 0, 11, 0)];
const rows = M.itemsForDay(items, now, {});
ok("rows sorted, all-day first", rows.map(r => r.title).join() === "Holiday,Standup,Hidden,Late");
ok("selection filters", M.itemsForDay(items, now, { calendarSelection: ["a"] }).every(r => r.sourceId === "a"));
ok("hide all-day", M.itemsForDay(items, now, { hideAllDayEvents: true }).every(r => !r.allDay));
ok("all-day end is exclusive", M.itemsForDay(items, at(12, 9, 0), {}).map(r => r.title).join() === "Tomorrow");
ok("scrollTarget skips all-day", rows[M.scrollTarget(rows, now)].title === "Standup");
ok("scrollTarget prefers running", rows[M.scrollTarget(rows, at(11, 11, 30))].title === "Hidden");
ok("scrollTarget -1 when over", M.scrollTarget(rows, at(11, 23, 0)) === -1);
const overnight = [ev("Night", 11, 22, 0, 23, 0, { end: iso(12, 2, 0) })];
ok("multi-day on both days", M.itemsForDay(overnight, at(12, 1, 0), {}).length === 1 && M.itemsForDay(overnight, at(13, 1, 0), {}).length === 0);

const gr = M.agendaGroups(items, now, 3, {});
ok("agenda groups skip empty days", gr.length === 2 && gr[0].rows.length === 4 && gr[1].rows.length === 1 && gr[1].day.getDate() === 12);
ok("agenda one day", M.agendaGroups(items, now, 1, {}).length === 1);
ok("agenda multi-day listed once", M.agendaGroups(overnight, at(11, 9, 0), 3, {}).length === 1);
ok("agenda title", M.agendaTitle(1) === "" && M.agendaTitle(7) === "Next 7 days" && M.agendaTitle(3) === "Next 3 days");
const nd = M.dueNotifications(items, at(11, 9, 20), 15, {});
ok("due notifications", nd.length === 1 && nd[0].title === "Standup" && nd[0].key === "a||" + items[1].start);
ok("none when off or too far", M.dueNotifications(items, at(11, 9, 20), 0, {}).length === 0 && M.dueNotifications(items, at(11, 9, 0), 5, {}).length === 0);
ok("none once started", M.dueNotifications(items, at(11, 9, 40), 15, {}).length === 0);
ok("all-day never notifies", M.dueNotifications([items[3]], at(11, 0, 0), 60, {}).length === 0);
ok("notify setting", M.resolveSettings({}).notifyMinutes === 5 && M.resolveSettings({ notifyMinutes: 0 }).notifyMinutes === 0 && M.resolveSettings({ notifyMinutes: 999 }).notifyMinutes === 60);
ok("safe urls", M.safeUrl("https://zoom.us/j/1") === "https://zoom.us/j/1" && M.safeUrl("http://localhost:5232/x") !== "" && M.safeUrl("mailto:") === "mailto:" && M.safeUrl("mailto:a@b.org") === "mailto:a@b.org");
ok("unsafe urls", M.safeUrl("javascript:alert(1)") === "" && M.safeUrl("file:///etc/passwd") === "" && M.safeUrl("https://u:p@evil.com/") === "" && M.safeUrl("https://a.com/x y") === "" && M.safeUrl("ftp://x") === "" && M.safeUrl("") === "" && M.safeUrl("https://x.com/\nrm") === "");
ok("attendee summary", M.attendeeSummary({ attendees: ["Ana", "Bo"], attendeeCount: 2 }) === "Ana, Bo" && M.attendeeSummary({ attendees: ["a", "b", "c", "d"], attendeeCount: 6 }) === "a, b, c +3" && M.attendeeSummary({}) === "");
// upcoming + chip
const up = M.upcoming(items, now, 3, {});
ok("upcoming order, no all-day", up.map(u => u.item.title).join() === "Standup,Hidden,Late");
ok("minutes to start", up[0].minutes === 30 && !up[0].now);
ok("upcoming limit", M.upcoming(items, now, 2, {}).length === 2);
ok("upcoming reaches tomorrow", M.upcoming(items, at(11, 23, 0), 3, {})[0].item.title === "Tomorrow");
ok("running event is now", M.upcoming(items, at(11, 9, 40), 1, {})[0].now === true);
ok("chip minutes", M.chip(up[0], now, s).text === "Standup · 30m");
const d = M.resolveSettings({});
ok("chip not soon at 30m (15 threshold)", M.chip(up[0], now, d).soon === false);
ok("chip soon at 10m", M.chip(M.upcoming(items, at(11, 9, 20), 1, {})[0], at(11, 9, 20), d).soon === true);
ok("chip now", M.chip(M.upcoming(items, at(11, 9, 40), 1, {})[0], at(11, 9, 40), s).text === "Standup · now");
ok("chip later today shows clock", M.chip(up[2], now, s).text === "Late · 15:00");
ok("chip tomorrow", M.chip(M.upcoming(items, at(11, 23, 0), 1, {})[0], at(11, 23, 0), s).text === "Tomorrow · tmrw 10:00");
ok("whenLabel", M.whenLabel(up[0], now) === "30m" && M.whenLabel(up[2], now) === "15:00");
ok("timeLabel", M.timeLabel(ev("x", 11, 9, 5, 10, 30)) === "09:05\u201310:30" && M.timeLabel(items[3]) === "All day");
ok("chip null", M.chip(null, now, s) === null);
ok("ellipsize", M.ellipsize("A very long meeting title indeed", 10) === "A very lo…");
ok("minutesLabel", M.minutesLabel(45) === "45m" && M.minutesLabel(90) === "1h30" && M.minutesLabel(120) === "2h" && M.minutesLabel(3000) === "2d");
const all = { event: true, timer: true, media: true, weather: true };
ok("extras order", M.extrasFor({ showEvent: true, showTimer: true, showMedia: true, showWeather: true }, all).join() === "event,timer,media,weather");
ok("extras need toggle and data", M.extrasFor({ showEvent: true, showTimer: false, showMedia: true, showWeather: true }, { event: true, timer: true, media: false, weather: true }).join() === "event,weather");
ok("no extras", M.extrasFor({}, all).length === 0);
ok("clock parts", JSON.stringify(M.clockParts("time")) === '{"date":false,"time":true}' && M.clockParts("date").time === false && M.clockParts("both").date && M.clockParts("both").time);

// month grid
const g = M.monthGrid(2026, 9, "monday");
ok("grid 42 cells", g.length === 42);
ok("oct 1 2026 is Thursday -> monday start col 3", g[3].date.getDate() === 1 && g[3].inMonth && !g[2].inMonth);
ok("sunday start", M.monthGrid(2026, 9, "sunday")[4].date.getDate() === 1);
ok("weekday headers", M.weekdayHeaders("monday").join() === "Mo,Tu,We,Th,Fr,Sa,Su" && M.weekdayHeaders("sunday")[0] === "Su");
ok("dots dedupe", M.dotsForDay([ev("x", 11, 9, 0, 10, 0), ev("y", 11, 11, 0, 12, 0)], now, {}).length === 1);

// sources
ok("file needs path", !M.validateSource({ kind: "file", path: " " }).ok && M.validateSource({ kind: "file", path: "~/a.ics" }).ok);
ok("bad kind", !M.validateSource({ kind: "nope" }).ok);
ok("webcal accepted", M.validateSource({ kind: "ics-url", url: "webcal://calendar.google.com/x/basic.ics" }).ok);
ok("http rejected", !M.validateSource({ kind: "ics-url", url: "http://example.com/a.ics" }).ok);
ok("http localhost ok", M.validateSource({ kind: "ics-url", url: "http://localhost:5232/a.ics" }).ok);
ok("userinfo rejected", !M.validateSource({ kind: "ics-url", url: "https://u:p@example.com/a" }).ok);
ok("caldav needs user", !M.validateSource({ kind: "caldav", url: "https://x.com/dav" }).ok && M.validateSource({ kind: "caldav", url: "https://x.com/dav", user: "me" }).ok);
ok("bad color", !M.validateSource({ kind: "file", path: "a", color: "red" }).ok);
ok("host only in detail", M.sourceDetail({ kind: "ics-url", url: "https://calendar.google.com/calendar/ical/SECRET/basic.ics" }) === "calendar.google.com");
ok("title falls back to host", M.sourceTitle({ kind: "ics-url", url: "https://calendar.google.com/x" }) === "calendar.google.com");
ok("error text", M.errorText("auth-error").length > 0 && M.errorText("http-404") === "Server said 404" && M.errorText("weird") === "Sync failed" && M.errorText("") === "");
ok("next color name", M.nextColorName([{ colorName: "accent" }]) === "blue");

const gfeed = { kind: "ics-url", url: "https://calendar.google.com/calendar/ical/jo%40gmail.com/private-abc123/basic.ics" };
const names = (o) => M.webLinks(o).map(l => l.name).join();
ok("google: calendar, tasks and gmail", names(gfeed) === "Google Calendar,Google Tasks,Gmail");
ok("google picks the signed-in account", M.webLinks(gfeed).every(l => l.url.indexOf("authuser=jo%40gmail.com") > 0));
ok("gmail link is for the signed-in account", M.webLinks(gfeed)[2].url === "https://mail.google.com/mail/u/0/?authuser=jo%40gmail.com");
ok("google links keep the key out", M.webLinks(gfeed).every(l => !/private|abc123/.test(l.url)));
ok("google shared calendar has no account", M.webLinks({ kind: "ics-url", url: "https://calendar.google.com/calendar/ical/abc123%40group.calendar.google.com/public/basic.ics" })[0].url === "https://calendar.google.com/calendar/u/0/r");
ok("outlook", names({ kind: "ics-url", url: "https://outlook.office365.com/owa/calendar/x/y/reachcalendar.ics" }) === "Outlook Calendar,Microsoft To Do,Outlook Mail");
ok("icloud", names({ kind: "caldav", url: "https://p12-caldav.icloud.com/123/calendars/" }) === "iCloud Calendar,iCloud Reminders,iCloud Mail");
ok("fastmail", names({ kind: "caldav", url: "https://caldav.fastmail.com/dav/" }) === "Fastmail Calendar,Fastmail");
ok("nextcloud", names({ kind: "caldav", url: "https://cloud.example.com/remote.php/dav/calendars/me/" }) === "Nextcloud Calendar,Nextcloud Tasks" && M.webLinks({ kind: "caldav", url: "https://cloud.example.com/remote.php/dav/calendars/me/" })[1].url === "https://cloud.example.com/apps/tasks");
ok("generic server", names({ kind: "caldav", url: "https://dav.example.org/cal/" }) === "dav.example.org" && M.webLinks({ kind: "caldav", url: "https://dav.example.org/cal/" })[0].url === "https://dav.example.org/");
ok("no links for files or lan", M.webLinks({ kind: "file", path: "/a.ics" }).length === 0 && M.webLinks({ kind: "vdir", path: "/d" }).length === 0 && M.webLinks({ kind: "caldav", url: "http://192.168.1.2/dav", allowLocalNetwork: true }).length === 0);
const both = M.webLinksFor([gfeed, Object.assign({}, gfeed), { kind: "caldav", url: "https://p1-caldav.icloud.com/x/", enabled: false }, { kind: "ics-url", url: "https://outlook.live.com/owa/calendar/a/b/c.ics" }]);
ok("links dedupe, skip disabled, keep order", both.map(l => l.name).join() === "Google Calendar,Google Tasks,Gmail,Outlook Calendar,Microsoft To Do,Outlook Mail");
// timers
const rem = JSON.stringify({ reminders: [
  { unit: "omarchy-reminder-25m-1", message: " Focus\n", minutes: 25, at: 2000 },
  { unit: "omarchy-reminder-5m-2", message: "", minutes: 5, at: 1000 },
  { unit: "evil; rm -rf", message: "x", minutes: 1, at: 5 }] });
const tl = M.parseReminders(rem);
ok("reminders sorted + filtered", tl.length === 2 && tl[0].label === "5-min timer" && tl[1].label === "Focus" && tl[0].at === 1000000);
ok("garbage reminders", M.parseReminders("nope").length === 0 && M.parseReminders("{}").length === 0);
ok("soonest", M.soonestTimer(tl, 500000).label === "5-min timer" && M.soonestTimer(tl, 5000000) === null);
ok("finished vs cancelled", M.finishedTimers(tl, [tl[1]], 1000000).length === 1 && M.finishedTimers(tl, [tl[1]], 10).length === 0);
ok("minutes valid", M.validMinutes(25) && !M.validMinutes(0) && !M.validMinutes(1.5) && !M.validMinutes(1441));
ok("remaining label", M.remainingLabel(65000) === "1:05" && M.remainingLabel(3725000) === "1:02:05" && M.remainingLabel(-5) === "0:00");

// weather & zones
ok("weather codes", M.weatherInfo(0, true).icon === "sun" && M.weatherInfo(0, false).icon === "moon" && M.weatherInfo(63).icon === "rain" && M.weatherInfo(96).icon === "storm");
const w = M.zoneWall(Date.UTC(2026, 9, 11, 12, 0, 0), 540);
ok("zone wall time", w.getHours() === 21 && w.getMinutes() === 0 && w.getDate() === 11);
ok("zone wall day rollover", M.zoneWall(Date.UTC(2026, 9, 11, 20, 0, 0), 540).getDate() === 12);
ok("offset label", M.offsetFromLocal(540, -420) === "+16h" && M.offsetFromLocal(-420, -420) === "same" && M.offsetFromLocal(330, 0) === "+5h30");
ok("zone city", M.zoneCity("America/New_York") === "New York");

console.log(failed ? failed + " FAILED" : "all passed");
process.exit(failed ? 1 : 0);
