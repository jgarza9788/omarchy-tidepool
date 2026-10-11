"""Small iCalendar reader: VEVENTs, the common RRULE subset, EXDATE and
RECURRENCE-ID overrides, expanded into a window. Standard library only.

Every returned time is a naive *local* datetime, so callers can compare and
display without carrying zones around.
"""
import datetime as dt
import re
from zoneinfo import ZoneInfo

DAYS = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
MAX_OCCURRENCES = 2000


def unfold(text):
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    return lines


def unescape(v):
    return (v.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
             .replace("\\;", ";").replace("\\\\", "\\"))


def parse_line(line):
    """'NAME;P=V:value' -> (name, {P: V}, value); respects quoted params."""
    in_q, split = False, -1
    for i, ch in enumerate(line):
        if ch == '"':
            in_q = not in_q
        elif ch == ":" and not in_q:
            split = i
            break
    if split < 0:
        return None
    head, value = line[:split], line[split + 1:]
    parts, cur, in_q = [], "", False
    for ch in head:
        if ch == '"':
            in_q = not in_q
            cur += ch
        elif ch == ";" and not in_q:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    params = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.upper()] = v.strip('"')
    return parts[0].upper(), params, value


def to_local(naive_or_aware):
    d = naive_or_aware
    if d.tzinfo is not None:
        d = d.astimezone().replace(tzinfo=None)
    return d


def parse_dt(value, params):
    """Return (datetime|date, all_day). Datetimes come back naive-local."""
    value = value.strip()
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        return dt.date(int(value[0:4]), int(value[4:6]), int(value[6:8])), True
    m = re.fullmatch(r"(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)", value)
    if not m:
        raise ValueError("bad date-time: " + value)
    y, mo, d, h, mi, s = (int(m.group(i)) for i in range(1, 7))
    base = dt.datetime(y, mo, d, h, mi, s)
    if m.group(7):
        return to_local(base.replace(tzinfo=dt.timezone.utc)), False
    tzid = params.get("TZID")
    if tzid:
        try:
            return to_local(base.replace(tzinfo=ZoneInfo(tzid))), False
        except Exception:
            pass
    return base, False


def parse_duration(v):
    m = re.fullmatch(r"([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?", v.strip())
    if not m:
        return dt.timedelta(0)
    sign = -1 if m.group(1) == "-" else 1
    w, d, h, mi, s = (int(g or 0) for g in m.groups()[1:])
    return sign * dt.timedelta(weeks=w, days=d, hours=h, minutes=mi, seconds=s)


def parse_rrule(v):
    out = {}
    for part in v.split(";"):
        if "=" in part:
            k, val = part.split("=", 1)
            out[k.upper()] = val
    return out


def _first_of(d):
    return d.date() if isinstance(d, dt.datetime) else d


def expand(start, rule, window_start, window_end, exdates):
    """Yield occurrence starts (same type as `start`) intersecting the window."""
    freq = rule.get("FREQ")
    if freq not in ("DAILY", "WEEKLY", "MONTHLY", "YEARLY"):
        yield start
        return
    interval = max(1, int(rule.get("INTERVAL", "1") or 1))
    count = int(rule["COUNT"]) if rule.get("COUNT") else None
    until = None
    if rule.get("UNTIL"):
        try:
            u, _ = parse_dt(rule["UNTIL"], {})
            until = u
        except ValueError:
            until = None
    byday = [x[-2:] for x in rule.get("BYDAY", "").split(",") if x]
    bymonthday = [int(x) for x in rule.get("BYMONTHDAY", "").split(",") if x]
    is_dt = isinstance(start, dt.datetime)
    t = start.time() if is_dt else None

    def make(day):
        return dt.datetime.combine(day, t) if is_dt else day

    def keep(occ):
        k = _first_of(occ)
        return k not in exdates

    produced = 0
    day0 = _first_of(start)
    if freq == "DAILY":
        n = 0
        while True:
            occ = make(day0 + dt.timedelta(days=n * interval))
            n += 1
            if until is not None and _first_of(occ) > _first_of(until):
                return
            produced += 1
            if count is not None and produced > count:
                return
            if _first_of(occ) > window_end or produced > MAX_OCCURRENCES:
                return
            if _first_of(occ) >= window_start and keep(occ):
                yield occ
    elif freq == "WEEKLY":
        wanted = [DAYS.index(x) for x in byday if x in DAYS] or [day0.weekday()]
        week0 = day0 - dt.timedelta(days=day0.weekday())
        n = 0
        while True:
            base = week0 + dt.timedelta(weeks=n * interval)
            for wd in sorted(wanted):
                day = base + dt.timedelta(days=wd)
                if day < day0:
                    continue
                occ = make(day)
                if until is not None and _first_of(occ) > _first_of(until):
                    return
                produced += 1
                if count is not None and produced > count:
                    return
                if produced > MAX_OCCURRENCES:
                    return
                if _first_of(occ) >= window_start and _first_of(occ) <= window_end and keep(occ):
                    yield occ
            if base > window_end:
                return
            n += 1
    elif freq == "MONTHLY":
        days = bymonthday or [day0.day]
        n = 0
        while True:
            total = day0.year * 12 + day0.month - 1 + n * interval
            y, m = divmod(total, 12)
            m += 1
            for d in sorted(days):
                try:
                    day = dt.date(y, m, d)
                except ValueError:
                    continue
                if day < day0:
                    continue
                occ = make(day)
                if until is not None and _first_of(occ) > _first_of(until):
                    return
                produced += 1
                if count is not None and produced > count:
                    return
                if produced > MAX_OCCURRENCES:
                    return
                if window_start <= _first_of(occ) <= window_end and keep(occ):
                    yield occ
            if dt.date(y, m, 1) > window_end:
                return
            n += 1
    else:  # YEARLY
        n = 0
        while True:
            y = day0.year + n * interval
            try:
                day = dt.date(y, day0.month, day0.day)
            except ValueError:
                n += 1
                continue
            occ = make(day)
            if until is not None and _first_of(occ) > _first_of(until):
                return
            produced += 1
            if count is not None and produced > count:
                return
            if day > window_end or produced > MAX_OCCURRENCES:
                return
            if day >= window_start and keep(occ):
                yield occ
            n += 1


MEETING_HOSTS = (
    "meet.google.com", "zoom.us", "zoomgov.com", "teams.microsoft.com", "teams.live.com",
    "webex.com", "whereby.com", "gotomeeting.com", "goto.com", "bluejeans.com", "meet.jit.si",
    "jitsi.org", "chime.aws", "around.co", "tuple.app", "huddle.slack.com", "discord.gg",
)
URL_RE = re.compile(r"https?://[^\s<>\"')\]]+", re.I)


def find_meeting_url(*texts):
    """The video-call link in an event's conference field, location, description
    or URL, in that order: the first link on a known meeting provider, else ''.
    (A plain website in the location is a venue, not a call.)"""
    for t in texts:
        for u in URL_RE.findall(t or ""):
            host = re.sub(r"^https?://", "", u, flags=re.I).split("/")[0].split("?")[0].lower()
            if any(host == h or host.endswith("." + h) for h in MEETING_HOSTS):
                return u.rstrip(".,;")
    return ""


def parse_events(text, window_start, window_end):
    """Return a list of {uid, title, location, allDay, start, end} where start
    and end are date (all-day) or naive-local datetime, for every occurrence
    that touches [window_start, window_end] (dates)."""
    blocks, cur = [], None
    for line in unfold(text):
        up = line.upper()
        if up == "BEGIN:VEVENT":
            cur = []
        elif up == "END:VEVENT":
            if cur is not None:
                blocks.append(cur)
            cur = None
        elif cur is not None:
            parsed = parse_line(line)
            if parsed:
                cur.append(parsed)

    masters, overrides = [], {}
    for props in blocks:
        ev = {"exdates": set(), "rrule": None}
        for name, params, value in props:
            try:
                if name == "UID":
                    ev["uid"] = value
                elif name == "SUMMARY":
                    ev["title"] = unescape(value)
                elif name == "LOCATION":
                    ev["location"] = unescape(value)
                elif name == "DESCRIPTION":
                    ev["description"] = unescape(value)
                elif name == "X-GOOGLE-CONFERENCE" or name == "X-MICROSOFT-SKYPETEAMSMEETINGURL":
                    ev["conference"] = value.strip()
                elif name == "URL":
                    ev["url"] = value.strip()
                elif name == "ATTENDEE":
                    cn = (params.get("CN") or "").strip()
                    who = cn or re.sub(r"^mailto:", "", value, flags=re.I)
                    if who:
                        ev.setdefault("attendees", []).append(who)
                elif name == "ORGANIZER":
                    cn = (params.get("CN") or "").strip()
                    ev["organizer"] = cn or re.sub(r"^mailto:", "", value, flags=re.I)
                elif name == "STATUS" and value.upper() == "CANCELLED":
                    ev["cancelled"] = True
                elif name == "DTSTART":
                    ev["start"], ev["allDay"] = parse_dt(value, params)
                elif name == "DTEND":
                    ev["end"], _ = parse_dt(value, params)
                elif name == "DURATION":
                    ev["duration"] = parse_duration(value)
                elif name == "RRULE":
                    ev["rrule"] = parse_rrule(value)
                elif name == "EXDATE":
                    for piece in value.split(","):
                        d, _ = parse_dt(piece, params)
                        ev["exdates"].add(_first_of(d))
                elif name == "RECURRENCE-ID":
                    d, _ = parse_dt(value, params)
                    ev["recurrence_id"] = _first_of(d)
            except ValueError:
                continue
        if "start" not in ev or ev.get("cancelled"):
            continue
        if ev.get("recurrence_id") is not None:
            overrides[(ev.get("uid"), ev["recurrence_id"])] = ev
        else:
            masters.append(ev)

    out = []

    def emit(ev, start):
        if ev["allDay"]:
            length = (ev["end"] - ev["start"]) if "end" in ev else dt.timedelta(days=1)
            end = start + length
        else:
            if "end" in ev:
                length = ev["end"] - ev["start"]
            else:
                length = ev.get("duration", dt.timedelta(0))
            end = start + length
        first = _first_of(start)
        last = _first_of(end - dt.timedelta(seconds=1)) if ev["allDay"] or end > start else first
        if last < first:
            last = first
        if last < window_start or first > window_end:
            return
        desc = (ev.get("description") or "").strip()
        out.append({"uid": ev.get("uid", ""), "title": ev.get("title", "(no title)"),
                    "location": ev.get("location", ""), "allDay": ev["allDay"],
                    "start": start, "end": end,
                    "description": desc[:600],
                    "meetingUrl": find_meeting_url(ev.get("conference"), ev.get("location"), desc, ev.get("url")),
                    "organizer": ev.get("organizer", ""),
                    "attendees": (ev.get("attendees") or [])[:8],
                    "attendeeCount": len(ev.get("attendees") or [])})

    for ev in masters:
        if ev["rrule"]:
            for occ in expand(ev["start"], ev["rrule"], window_start, window_end, ev["exdates"]):
                ov = overrides.get((ev.get("uid"), _first_of(occ)))
                if ov:
                    continue
                emit(ev, occ)
        else:
            emit(ev, ev["start"])
    for ov in overrides.values():
        emit(ov, ov["start"])
    return out
