"""Tidepool backend: calendar sources (file / vdir / ics-url / caldav), weather
and world-clock offsets. Standard library only.

Each CLI command reads one JSON object on stdin and prints one JSON object on
the last stdout line. Errors come back as {"error": "..."}; per-source
failures are reported as short codes in {"errors": {sourceId: code}} so the
panel can show them without failing the whole sync.

State (override with TIDEPOOL_STATE_DIR):
  <state>/cache.json   last sync result, rendered instantly on startup
  <state>/geo.json     geocoded city -> lat/lon
Passwords live in the Secret Service (service=tidepool, source=<id>); they
never touch a JSON file.
"""
import base64
import datetime as dt
import fcntl
import hashlib
import http.client
import ipaddress
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from zoneinfo import ZoneInfo

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ics  # noqa: E402

HTTP_TIMEOUT = 20
MAX_BODY = 8 * 1024 * 1024
MAX_SOURCES = 32
MAX_REDIRECTS = 4
KINDS = ("file", "vdir", "ics-url", "caldav")
SECRET_SERVICE = "tidepool"
OPEN_METEO_GEO = "https://geocoding-api.open-meteo.com/v1/search"
OPEN_METEO = "https://api.open-meteo.com/v1/forecast"


class HelperError(Exception):
    def __init__(self, message, code="error"):
        super().__init__(message)
        self.code = code


# ── State ────────────────────────────────────────────────────────────────────
def state_dir():
    d = os.environ.get("TIDEPOOL_STATE_DIR")
    if not d:
        base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
        d = os.path.join(base, "jgarza.tidepool")
    return d


def read_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path, data):
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f)
    os.replace(tmp, path)


# ── Settings file ────────────────────────────────────────────────────────────
SETTINGS_VERSION = 1
SOURCE_KEYS = ("kind", "path", "url", "user", "label", "color", "colorName", "enabled", "allowLocalNetwork")
SETTING_DEFAULTS = {
    "calendarSources": [], "calendarSelection": [], "calendarRefresh": 15,
    "hideAllDayEvents": False, "autoScrollToNextEvent": True, "showFullEventTitles": False,
    "agendaDays": 1, "alarms": [],
}
MAX_ALARMS = 20
AGENDA_DAYS = (1, 3, 7, 14, 30)


def config_dir():
    d = os.environ.get("TIDEPOOL_CONFIG_DIR")
    return d or os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"),
                             "jgarza.tidepool")


def settings_path():
    return os.path.join(config_dir(), "settings.json")


def clean_source(raw):
    if not isinstance(raw, dict) or raw.get("kind") not in KINDS:
        return None
    out = {}
    for k in SOURCE_KEYS:
        v = raw.get(k)
        if v is None or v == "":
            continue
        if k in ("enabled", "allowLocalNetwork"):
            out[k] = bool(v)
        elif isinstance(v, str):
            out[k] = v.strip()[:2048]
    if out.get("color") and not (len(out["color"]) == 7 and out["color"][0] == "#"):
        out.pop("color")
    return out


def clean_settings(values):
    out = dict(SETTING_DEFAULTS)
    if not isinstance(values, dict):
        return out
    srcs = [clean_source(s) for s in (values.get("calendarSources") or [])[:MAX_SOURCES]]
    out["calendarSources"] = [s for s in srcs if s]
    ids = {source_id(s) for s in out["calendarSources"]}
    sel = values.get("calendarSelection") or []
    out["calendarSelection"] = [i for i in sel if isinstance(i, str) and i in ids]
    try:
        out["calendarRefresh"] = max(5, min(1440, int(values.get("calendarRefresh", 15))))
    except (TypeError, ValueError):
        pass
    try:
        days = int(values.get("agendaDays", 1))
        out["agendaDays"] = days if days in AGENDA_DAYS else 1
    except (TypeError, ValueError):
        pass
    for k in ("hideAllDayEvents", "autoScrollToNextEvent", "showFullEventTitles"):
        if k in values:
            out[k] = bool(values[k])
    alarms = [clean_alarm(a) for a in (values.get("alarms") or [])[:MAX_ALARMS]] if isinstance(values.get("alarms"), list) else []
    seen = set()
    out["alarms"] = [a for a in alarms if a and not (a["id"] in seen or seen.add(a["id"]))]
    return out


def with_ids(values):
    return {"values": values, "ids": [source_id(x) for x in values["calendarSources"]]}


def settings_get():
    data = read_json(settings_path(), {})
    return with_ids(clean_settings(data.get("values") if isinstance(data, dict) else {}))


def settings_set(args):
    # Two quick toggles can run two helpers at once; take a lock so neither's
    # change is lost to the other's read-modify-write.
    os.makedirs(config_dir(), mode=0o700, exist_ok=True)
    with open(os.path.join(config_dir(), ".lock"), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _settings_set_locked(args)


def _settings_set_locked(args):
    current = settings_get()["values"]
    patch = args.get("values")
    if not isinstance(patch, dict):
        raise HelperError("bad request")
    merged = dict(current)
    merged.update({k: v for k, v in patch.items() if k in SETTING_DEFAULTS})
    cleaned = clean_settings(merged)
    write_json(settings_path(), {"version": SETTINGS_VERSION, "values": cleaned})
    return with_ids(cleaned)


def import_nookisle(args):
    """Copy calendar sources from ~/.config/nookisle/settings.json (sources only)."""
    path = args.get("path") or os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config"),
                                            "nookisle", "settings.json")
    data = read_json(path, None)
    if not isinstance(data, dict):
        raise HelperError("no nookisle settings found", "not-found")
    vals = data.get("values") if isinstance(data.get("values"), dict) else data
    listed = vals.get("calendarSources")
    found = [clean_source(s) for s in (listed if isinstance(listed, list) else [])]
    found = [s for s in found if s]
    current = settings_get()["values"]
    have = {source_id(s) for s in current["calendarSources"]}
    added = [s for s in found if source_id(s) not in have]
    current["calendarSources"] = (current["calendarSources"] + added)[:MAX_SOURCES]
    out = settings_set({"values": {"calendarSources": current["calendarSources"]}})
    out["added"] = len(added)
    return out


# ── Sources ──────────────────────────────────────────────────────────────────
def source_id(src):
    key = "\n".join([src.get("kind", ""), src.get("path", "") or "", src.get("url", "") or "", src.get("user", "") or ""])
    return hashlib.sha256(key.encode()).hexdigest()[:16]


def _is_private(ip):
    a = ipaddress.ip_address(ip)
    cgnat = ipaddress.ip_network("100.64.0.0/10")
    return (a.is_private or a.is_loopback or a.is_link_local or a.is_reserved or a.is_multicast
            or a.is_unspecified or (a.version == 4 and a in cgnat))


LOOPBACK_HOSTS = ("localhost", "127.0.0.1", "::1")


def check_url(url, allow_local=False, loopback_ok=None):
    """Validate a remote calendar URL; return it with webcal:// -> https://.
    `loopback_ok`: may this request go to localhost? Defaults to `allow_local`;
    http_request passes True only when the *first* URL was a loopback one, so a
    public server cannot redirect us to a service on this machine."""
    if loopback_ok is None:
        loopback_ok = allow_local
    if url.startswith("webcal://"):
        url = "https://" + url[len("webcal://"):]
    parts = urllib.parse.urlsplit(url)
    host = parts.hostname or ""
    if parts.username or parts.password:
        raise HelperError("credentials in URL", "bad-url")
    if parts.scheme not in ("http", "https") or not host:
        raise HelperError("only https URLs are allowed", "bad-url")
    is_loopback = host in LOOPBACK_HOSTS
    if parts.scheme == "http" and not (is_loopback and loopback_ok):
        raise HelperError("only https URLs are allowed", "bad-url")
    if allow_local or (is_loopback and loopback_ok):
        return url
    if is_loopback:
        raise HelperError("private address", "private-address")
    try:
        infos = socket.getaddrinfo(host, parts.port or 443, proto=socket.IPPROTO_TCP)
    except OSError:
        raise HelperError("could not resolve host", "network")
    for info in infos:
        if _is_private(info[4][0]):
            raise HelperError("private address", "private-address")
    return url


# The connection itself re-checks the address it actually connects to. Checking
# only the name beforehand would let a DNS server answer "public" for the check
# and "10.0.0.1" for the connect (DNS rebinding).
_POLICY = {"allow_local": False, "loopback_ok": False}


def _pinned_connection(address, timeout=None, source_address=None):
    host, port = address
    last = None
    blocked = False
    for family, socktype, proto, _, sockaddr in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM):
        ip = sockaddr[0]
        if not _POLICY["allow_local"] and _is_private(ip):
            if not (_POLICY["loopback_ok"] and ipaddress.ip_address(ip).is_loopback and host in LOOPBACK_HOSTS):
                blocked = True
                continue
        try:
            return socket.create_connection((ip, port), timeout, source_address)
        except OSError as e:
            last = e
    if blocked and last is None:
        raise HelperError("private address", "private-address")
    raise last or OSError("could not connect")


class _PinnedHTTP(http.client.HTTPConnection):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self._create_connection = _pinned_connection


class _PinnedHTTPS(http.client.HTTPSConnection):
    def __init__(self, *a, **k):
        super().__init__(*a, **k)
        self._create_connection = _pinned_connection


class _HTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, req):
        return self.do_open(_PinnedHTTP, req)


class _HTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):
        return self.do_open(_PinnedHTTPS, req, context=self._context)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_opener = urllib.request.build_opener(_NoRedirect, _HTTPHandler, _HTTPSHandler)


def http_request(method, url, headers=None, body=None, allow_local=False):
    """Return (status, headers, bytes), following up to MAX_REDIRECTS hops that
    each pass check_url (so a public host cannot bounce us to the LAN or to
    localhost). Credentials are not forwarded to a different host."""
    headers = dict(headers or {})
    first_host = (urllib.parse.urlsplit(url.replace("webcal://", "https://", 1)).hostname or "")
    loopback_ok = allow_local or first_host in LOOPBACK_HOSTS
    _POLICY["allow_local"] = bool(allow_local)
    _POLICY["loopback_ok"] = bool(loopback_ok)
    host = first_host
    for _ in range(MAX_REDIRECTS + 1):
        url = check_url(url, allow_local, loopback_ok)
        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with _opener.open(req, timeout=HTTP_TIMEOUT) as r:
                return r.status, dict(r.headers), r.read(MAX_BODY + 1)[:MAX_BODY]
        except urllib.error.HTTPError as e:
            try:
                if e.code in (301, 302, 303, 307, 308) and e.headers.get("Location"):
                    nxt = urllib.parse.urljoin(url, e.headers["Location"])
                    try:
                        url = check_url(nxt, allow_local, loopback_ok)
                    except HelperError:
                        raise HelperError("redirect refused", "redirect-refused")
                    new_host = urllib.parse.urlsplit(url).hostname or ""
                    if new_host != host:                      # never send a login to another host
                        headers = {k: v for k, v in headers.items() if k.lower() != "authorization"}
                        host = new_host
                    continue
                return e.code, dict(e.headers or {}), (e.read(MAX_BODY) if e.fp else b"")
            finally:
                e.close()
        except TimeoutError:
            raise HelperError("timed out", "timeout")
        except (urllib.error.URLError, OSError) as e:
            if "timed out" in str(getattr(e, "reason", e)):
                raise HelperError("timed out", "timeout")
            raise HelperError("network error: %s" % getattr(e, "reason", e), "network")
    raise HelperError("too many redirects", "redirect-refused")


# ── Secret service ───────────────────────────────────────────────────────────
def secret_lookup(sid):
    try:
        p = subprocess.run(["secret-tool", "lookup", "service", SECRET_SERVICE, "source", sid],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        raise HelperError("secret service unavailable", "secret-service-locked")
    if p.returncode != 0 or not p.stdout:
        raise HelperError("no password stored", "auth-error")
    return p.stdout.rstrip("\n")


def secret_store(sid, label, password):
    try:
        p = subprocess.run(["secret-tool", "store", "--label", "Tidepool: " + label,
                            "service", SECRET_SERVICE, "source", sid],
                           input=password, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        raise HelperError("secret service unavailable", "secret-service-locked")
    if p.returncode != 0:
        raise HelperError("could not store password", "secret-service-locked")
    return {"ok": True}


def secret_clear(sid):
    try:
        subprocess.run(["secret-tool", "clear", "service", SECRET_SERVICE, "source", sid],
                       capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return {"ok": True}


# ── Window / items ───────────────────────────────────────────────────────────
def sync_window(today=None, back=7, ahead=45):
    today = today or dt.date.today()
    return today - dt.timedelta(days=back), today + dt.timedelta(days=ahead)


def iso(v):
    if isinstance(v, dt.datetime):
        return v.strftime("%Y-%m-%dT%H:%M:%S")
    return v.isoformat()


def make_items(src, calendar, raw_events):
    out = []
    for e in raw_events:
        out.append({
            "sourceId": src["id"], "calendar": calendar, "uid": e.get("uid", ""),
            "title": e["title"], "location": e.get("location", ""),
            "allDay": bool(e["allDay"]), "start": iso(e["start"]), "end": iso(e["end"]),
            "color": src.get("color", ""),
            "description": e.get("description", ""), "meetingUrl": e.get("meetingUrl", ""),
            "organizer": e.get("organizer", ""), "attendees": e.get("attendees", []),
            "attendeeCount": e.get("attendeeCount", 0),
        })
    return out


def fetch_file(src, w_start, w_end):
    path = os.path.expanduser(src.get("path", ""))
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read(MAX_BODY)
    except OSError:
        raise HelperError("cannot read file", "read-error")
    return make_items(src, src.get("label") or os.path.basename(path), ics.parse_events(text, w_start, w_end))


def fetch_vdir(src, w_start, w_end):
    path = os.path.expanduser(src.get("path", ""))
    try:
        names = sorted(n for n in os.listdir(path) if n.endswith(".ics"))
    except OSError:
        raise HelperError("cannot read folder", "read-error")
    raw = []
    for n in names[:2000]:
        try:
            with open(os.path.join(path, n), "r", encoding="utf-8", errors="replace") as f:
                raw += ics.parse_events(f.read(MAX_BODY), w_start, w_end)
        except OSError:
            continue
    return make_items(src, src.get("label") or os.path.basename(path.rstrip("/")), raw)


def fetch_ics_url(src, w_start, w_end):
    status, _, body = http_request("GET", src.get("url", ""), {"Accept": "text/calendar"},
                                   allow_local=bool(src.get("allowLocalNetwork")))
    if status in (401, 403):
        raise HelperError("not authorised", "auth-error")
    if status >= 400:
        raise HelperError("HTTP %d" % status, "http-%d" % status)
    text = body.decode("utf-8", "replace")
    if "BEGIN:VCALENDAR" not in text:
        raise HelperError("not an iCalendar feed", "bad-feed")
    return make_items(src, src.get("label") or "Calendar", ics.parse_events(text, w_start, w_end))


# CalDAV
NS = {"d": "DAV:", "c": "urn:ietf:params:xml:ns:caldav"}


def _basic(user, password):
    return "Basic " + base64.b64encode(("%s:%s" % (user, password)).encode()).decode()


def dav(method, url, src, password, body, depth=None):
    headers = {"Authorization": _basic(src.get("user", ""), password),
               "Content-Type": "application/xml; charset=utf-8"}
    if depth is not None:
        headers["Depth"] = str(depth)
    status, _, raw = http_request(method, url, headers, body.encode(), allow_local=bool(src.get("allowLocalNetwork")))
    if status in (401, 403):
        raise HelperError("login rejected", "auth-error")
    if status >= 400:
        raise HelperError("CalDAV %s failed: HTTP %d" % (method, status), "http-%d" % status)
    try:
        return ET.fromstring(raw)
    except ET.ParseError:
        raise HelperError("invalid XML from server", "bad-feed")


def _hrefs(root, path):
    return [(e.text or "").strip() for e in root.iterfind(path, NS) if e.text]


def caldav_calendars(src, password):
    """Return [(calendar_url, name)] for a server / principal / calendar URL."""
    url = src["url"]
    prop = ('<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>'
            '<d:resourcetype/><d:displayname/><d:current-user-principal/><c:calendar-home-set/>'
            '</d:prop></d:propfind>')
    root = dav("PROPFIND", url, src, password, prop, depth=0)
    if root.find(".//d:resourcetype/c:calendar", NS) is not None:
        return [(url, root.findtext(".//d:displayname", "", NS) or "Calendar")]
    home = _hrefs(root, ".//c:calendar-home-set/d:href")
    if not home:
        principal = _hrefs(root, ".//d:current-user-principal/d:href")
        if principal:
            root2 = dav("PROPFIND", urllib.parse.urljoin(url, principal[0]), src, password, prop, depth=0)
            home = _hrefs(root2, ".//c:calendar-home-set/d:href")
    if not home:
        raise HelperError("no calendars found", "bad-feed")
    home_url = urllib.parse.urljoin(url, home[0])
    listing = dav("PROPFIND", home_url, src, password, prop, depth=1)
    out = []
    for resp in listing.iterfind("d:response", NS):
        if resp.find(".//d:resourcetype/c:calendar", NS) is None:
            continue
        href = (resp.findtext("d:href", "", NS) or "").strip()
        out.append((urllib.parse.urljoin(home_url, href), resp.findtext(".//d:displayname", "", NS) or "Calendar"))
    if not out:
        raise HelperError("no calendars found", "bad-feed")
    return out


def fetch_caldav(src, w_start, w_end):
    password = secret_lookup(src["id"])
    fmt = "%Y%m%dT000000Z"
    s = dt.datetime.combine(w_start - dt.timedelta(days=1), dt.time())
    e = dt.datetime.combine(w_end + dt.timedelta(days=2), dt.time())
    query = ('<?xml version="1.0"?><c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
             '<d:prop><c:calendar-data/></d:prop><c:filter><c:comp-filter name="VCALENDAR">'
             '<c:comp-filter name="VEVENT"><c:time-range start="%s" end="%s"/></c:comp-filter>'
             '</c:comp-filter></c:filter></c:calendar-query>') % (s.strftime(fmt), e.strftime(fmt))
    out = []
    for cal_url, name in caldav_calendars(src, password):
        root = dav("REPORT", cal_url, src, password, query, depth=1)
        for node in root.iterfind(".//c:calendar-data", NS):
            if node.text:
                out += make_items(src, src.get("label") or name, ics.parse_events(node.text, w_start, w_end))
    return out


FETCHERS = {"file": fetch_file, "vdir": fetch_vdir, "ics-url": fetch_ics_url, "caldav": fetch_caldav}


def sync(args):
    sources = args.get("sources") or []
    if not isinstance(sources, list):
        raise HelperError("sources must be a list")
    w_start, w_end = sync_window(back=int(args.get("back", 7)), ahead=int(args.get("ahead", 45)))
    items, errors = [], {}
    for raw in sources[:MAX_SOURCES]:
        if not isinstance(raw, dict) or raw.get("kind") not in KINDS:
            continue
        src = dict(raw)
        src["id"] = source_id(src)
        if raw.get("enabled") is False:
            continue
        try:
            items += FETCHERS[src["kind"]](src, w_start, w_end)
        except HelperError as e:
            errors[src["id"]] = e.code
        except Exception:  # a parser bug in one feed must not sink the others
            errors[src["id"]] = "bad-feed"
    result = {"items": items, "errors": errors, "syncedAt": dt.datetime.now().strftime("%Y-%m-%dT%H:%M:%S")}
    write_json(os.path.join(state_dir(), "cache.json"), result)
    return result


def sources_ids(args):
    out = []
    for raw in args.get("sources") or []:
        if isinstance(raw, dict) and raw.get("kind") in KINDS:
            out.append(source_id(raw))
    return {"ids": out}


# ── Weather ──────────────────────────────────────────────────────────────────
def json_get(url):
    status, _, body = http_request("GET", url, {"Accept": "application/json"})
    if status >= 400:
        raise HelperError("HTTP %d" % status, "http-%d" % status)
    try:
        return json.loads(body.decode("utf-8"))
    except ValueError:
        raise HelperError("bad response", "bad-feed")


def place_label(r):
    """'Austin, Texas, US' from an Open-Meteo geocoding result."""
    parts = [r.get("name", ""), r.get("admin1", ""), r.get("country_code", "")]
    out = []
    for p in parts:
        if p and p not in out:
            out.append(p)
    return ", ".join(out)


def search_city(args):
    """Places matching what has been typed so far, for the settings dropdown."""
    query = str(args.get("query", "")).strip()[:80]
    if len(query) < 2:
        return {"places": []}
    data = json_get(OPEN_METEO_GEO + "?" + urllib.parse.urlencode({"name": query, "count": 8, "language": "en"}))
    places = []
    for r in data.get("results") or []:
        try:
            places.append({"label": place_label(r), "name": r.get("name", ""), "region": r.get("admin1", ""),
                           "country": r.get("country_code", ""), "lat": float(r["latitude"]), "lon": float(r["longitude"])})
        except (KeyError, TypeError, ValueError):
            continue
    return {"places": places}


def geocode(city):
    cache_path = os.path.join(state_dir(), "geo.json")
    cache = read_json(cache_path, {})
    key = city.strip().lower()
    if key in cache:
        return cache[key]
    data = json_get(OPEN_METEO_GEO + "?" + urllib.parse.urlencode({"name": city, "count": 1, "language": "en"}))
    results = data.get("results") or []
    if not results:
        raise HelperError("city not found", "not-found")
    r = results[0]
    place = {"name": r.get("name", city), "region": r.get("admin1", ""), "country": r.get("country_code", ""),
             "lat": r["latitude"], "lon": r["longitude"]}
    cache[key] = place
    write_json(cache_path, cache)
    return place


def known_place(args):
    """A place picked from the dropdown carries its own coordinates."""
    try:
        lat, lon = float(args.get("lat")), float(args.get("lon"))
    except (TypeError, ValueError):
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    label = str(args.get("city", "")).strip()
    bits = [b.strip() for b in label.split(",")]
    return {"name": bits[0] or label, "region": bits[1] if len(bits) > 2 else "",
            "country": bits[-1] if len(bits) > 1 else "", "lat": lat, "lon": lon}


HOURLY_COUNT = 12


def _col(block, key, i, default=None):
    """The i-th value of an Open-Meteo column, or default if it is missing/short."""
    vals = block.get(key) or []
    return vals[i] if i < len(vals) and vals[i] is not None else default


def hourly_rows(hourly):
    """Open-Meteo's column-per-field `hourly` block -> one dict per hour."""
    return [{"time": t, "temp": _col(hourly, "temperature_2m", i, 0),
             "rain": _col(hourly, "precipitation_probability", i, 0),
             "code": _col(hourly, "weather_code", i, 0),
             "isDay": bool(_col(hourly, "is_day", i, 1)),
             "uv": _col(hourly, "uv_index", i, 0)}
            for i, t in enumerate((hourly.get("time") or [])[:HOURLY_COUNT])]


def weather(args):
    city = (args.get("city") or "").strip()
    place = known_place(args)
    if place is None:
        if not city:
            raise HelperError("no city set", "no-city")
        place = geocode(city)
    imperial = args.get("units") == "imperial"
    q = {"latitude": place["lat"], "longitude": place["lon"], "timezone": "auto", "forecast_days": 5,
         "current": "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day",
         "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max",
         "hourly": "temperature_2m,precipitation_probability,weather_code,is_day,uv_index",
         "forecast_hours": HOURLY_COUNT}
    if imperial:
        q.update(temperature_unit="fahrenheit", wind_speed_unit="mph")
    data = json_get(OPEN_METEO + "?" + urllib.parse.urlencode(q))
    cur, daily = data.get("current") or {}, data.get("daily") or {}
    hours = hourly_rows(data.get("hourly") or {})
    days = []
    for i, day in enumerate(daily.get("time") or []):
        days.append({"date": day, "code": (daily.get("weather_code") or [0] * 99)[i],
                     "max": (daily.get("temperature_2m_max") or [0] * 99)[i],
                     "min": (daily.get("temperature_2m_min") or [0] * 99)[i],
                     "rain": _col(daily, "precipitation_probability_max", i, 0),
                     "uv": _col(daily, "uv_index_max", i, 0)})
    return {"place": place, "units": "imperial" if imperial else "metric",
            "current": {"temp": cur.get("temperature_2m"), "feels": cur.get("apparent_temperature"),
                        "code": cur.get("weather_code", 0), "wind": cur.get("wind_speed_10m"),
                        "isDay": bool(cur.get("is_day", 1)),
                        "uv": hours[0]["uv"] if hours else 0},
            "hours": hours, "days": days}


# ── World clocks ─────────────────────────────────────────────────────────────
def zones(args):
    now = dt.datetime.now(dt.timezone.utc)
    out = {}
    for name in (args.get("zones") or [])[:12]:
        try:
            z = now.astimezone(ZoneInfo(str(name)))
        except Exception:
            out[str(name)] = {"error": "unknown zone"}
            continue
        out[str(name)] = {"offsetMin": int(z.utcoffset().total_seconds() // 60), "abbr": z.tzname() or ""}
    return {"zones": out}


def search_zones(args):
    """Time zones matching what was typed ('tokyo', 'new york', 'est'), best first."""
    import zoneinfo
    q = str(args.get("query", "")).strip().lower().replace("_", " ")[:60]
    if len(q) < 2:
        return {"zones": []}
    ranked = []
    for name in zoneinfo.available_timezones():
        if name.startswith(("Etc/", "posix/", "right/", "SystemV/")) or name in ("localtime", "Factory"):
            continue
        low = name.lower().replace("_", " ")
        city = low.rsplit("/", 1)[-1]
        if q == city or q == low:
            rank = 0
        elif city.startswith(q):
            rank = 1
        elif q in city:
            rank = 2
        elif q in low:
            rank = 3
        else:
            continue
        ranked.append((rank, len(name), name))
    ranked.sort()
    out = []
    for _, _, name in ranked[:8]:
        parts = name.split("/")
        out.append({"zone": name, "city": parts[-1].replace("_", " "),
                    "region": " / ".join(p.replace("_", " ") for p in parts[:-1])})
    return {"zones": out}


# ── Alarms ───────────────────────────────────────────────────────────────────
# Each enabled alarm is a transient systemd user timer (tidepool-alarm-<id>)
# that runs notify-send, so it survives a shell restart and handles sleep and
# daylight-saving changes. Days are 0 = Monday ... 6 = Sunday.
ALARM_ID_RE = re.compile(r"^[a-z0-9]{6,16}$")
ALARM_TIME_RE = re.compile(r"^([01]?\d|2[0-3]):([0-5]\d)$")
DAY_NAMES = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


def next_occurrence(hour, minute, now):
    """The next date (as datetime) at hour:minute that is still ahead of `now`."""
    at = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    return at if at > now else at + dt.timedelta(days=1)


def clean_alarm(raw, now=None):
    if not isinstance(raw, dict):
        return None
    m = ALARM_TIME_RE.match(str(raw.get("time", "")).strip())
    if not m:
        return None
    hour, minute = int(m.group(1)), int(m.group(2))
    aid = str(raw.get("id", ""))
    if not ALARM_ID_RE.match(aid):
        aid = hashlib.sha256(os.urandom(16)).hexdigest()[:10]
    days = sorted({d for d in (raw.get("days") or []) if isinstance(d, int) and not isinstance(d, bool) and 0 <= d <= 6}) \
        if isinstance(raw.get("days"), list) else []
    label = re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f]", " ", str(raw.get("label") or ""))).strip()[:80]
    out = {"id": aid, "time": "%02d:%02d" % (hour, minute), "days": days, "label": label, "enabled": bool(raw.get("enabled", True))}
    if not days and out["enabled"]:
        # A one-off alarm remembers the day it is set for, so it fires once.
        date = str(raw.get("date") or "")
        try:
            dt.date.fromisoformat(date)
        except ValueError:
            date = next_occurrence(hour, minute, now or dt.datetime.now()).date().isoformat()
        out["date"] = date
    return out


def alarm_calendar(alarm):
    """systemd OnCalendar= expression for a cleaned alarm."""
    hhmm = alarm["time"] + ":00"
    if alarm["days"]:
        if len(alarm["days"]) == 7:
            return "*-*-* " + hhmm
        return ",".join(DAY_NAMES[d] for d in alarm["days"]) + " *-*-* " + hhmm
    return alarm["date"] + " " + hhmm


def alarm_expired(alarm, now):
    """A one-off alarm whose moment has passed."""
    if alarm["days"] or not alarm.get("date"):
        return False
    h, m = alarm["time"].split(":")
    try:
        when = dt.datetime.combine(dt.date.fromisoformat(alarm["date"]), dt.time(int(h), int(m)))
    except ValueError:
        return True
    return when <= now


def alarm_unit(alarm):
    return "tidepool-alarm-" + alarm["id"]


def alarms_sync(args=None):
    """Make the systemd user timers match the saved alarms: stop every
    tidepool-alarm-* timer, then start one per enabled alarm. One-off alarms
    that have already gone off are switched off in the saved settings."""
    now = dt.datetime.now()
    current = settings_get()["values"]
    alarms, changed = [], False
    for a in current["alarms"]:
        if a["enabled"] and alarm_expired(a, now):
            a = dict(a, enabled=False)
            a.pop("date", None)
            changed = True
        alarms.append(a)
    if changed:
        current = settings_set({"values": {"alarms": alarms}})["values"]
        alarms = current["alarms"]
    listed = _run(["systemctl", "--user", "list-units", "--all", "--plain", "--no-legend", "--type=timer", "tidepool-alarm-*.timer"], 10)
    for line in (listed.stdout.splitlines() if listed and listed.returncode == 0 else []):
        unit = line.split(None, 1)[0] if line.strip() else ""
        if re.match(r"^tidepool-alarm-[a-z0-9]+\.timer$", unit):
            _run(["systemctl", "--user", "stop", unit, unit[:-6] + ".service"], 10)
    started = 0
    for a in alarms:
        if not a["enabled"]:
            continue
        body = a["time"] + (" · " + ", ".join(DAY_NAMES[d] for d in a["days"]) if a["days"] else "")
        r = _run(["systemd-run", "--user", "--quiet", "--collect", "--unit=" + alarm_unit(a),
                  "--description=Tidepool alarm", "--on-calendar=" + alarm_calendar(a), "--timer-property=AccuracySec=1s",
                  "notify-send", "-a", "Tidepool", "-u", "critical", "-i", "alarm-symbolic", "--",
                  a["label"] or "Alarm", body], 10)
        if r is not None and r.returncode == 0:
            started += 1
    return {"values": current, "started": started}


# ── Event notifications ──────────────────────────────────────────────────────
def send_notification(title, body, urgency="normal"):
    try:
        subprocess.run(["notify-send", "-a", "Tidepool", "-u", urgency, "-i", "appointment-soon", "--", title, body],
                       capture_output=True, timeout=10)
        return True
    except (OSError, subprocess.TimeoutExpired):
        return False


def notify_due(args):
    """Send a desktop notification for each event starting within `minutes`,
    once per event (remembered in notified.json, pruned after two days)."""
    path = os.path.join(state_dir(), "notified.json")
    seen = read_json(path, {})
    if not isinstance(seen, dict):
        seen = {}
    now = time.time()
    seen = {k: t for k, t in seen.items() if isinstance(t, (int, float)) and now - t < 2 * 86400}
    sent = 0
    for it in (args.get("items") or [])[:20]:
        key = str(it.get("key", ""))
        if not key or key in seen:
            continue
        try:
            start = dt.datetime.fromisoformat(str(it.get("start")))
        except ValueError:
            continue
        mins = int((start - dt.datetime.now()).total_seconds() // 60) + 1
        if mins < 0 or mins > 120:
            continue
        title = str(it.get("title") or "Event")[:120]
        bits = ["Starting now" if mins <= 0 else "Starts in %d min" % mins]
        if it.get("location"):
            bits.append(str(it["location"])[:100])
        if it.get("url"):
            bits.append("Join: " + str(it["url"])[:200])
        if send_notification(title, "\n".join(bits)):
            seen[key] = now
            sent += 1
    write_json(path, seen)
    return {"sent": sent}


# ── Focus the window of a media app ──────────────────────────────────────────
DBUS_NAME_RE = re.compile(r"^org\.mpris\.MediaPlayer2\.[A-Za-z0-9_.\-]+$")
ADDRESS_RE = re.compile(r"^0x[0-9a-f]+$")


def ppid_of(pid):
    """Parent pid from /proc, or 0."""
    try:
        with open("/proc/%d/stat" % pid, "r") as f:
            data = f.read()
        return int(data[data.rindex(")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        return 0


def ancestors(pid, parent=ppid_of, limit=16):
    """[pid, parent, grandparent, ...], stopping at init."""
    chain = []
    while pid > 1 and pid not in chain and len(chain) < limit:
        chain.append(pid)
        pid = parent(pid)
    return chain


def _title_score(client, hints):
    title = (client.get("title") or "").lower()
    score = 0
    for key, weight in (("title", 3), ("identity", 1)):
        want = (hints.get(key) or "").strip().lower()
        if want and want in title:
            score += weight
    return score


def pick_window(clients, chain, hints):
    """The window that belongs to a media app: the one owned by the app's
    process or the nearest parent that owns a window (a TUI lives inside its
    terminal); failing that, the best class / title match. hints: title
    (current track), identity, desktopEntry. None if nothing fits."""
    usable = [c for c in clients if c.get("mapped", True) and not c.get("hidden", False)]
    for pid in chain:
        owned = [c for c in usable if c.get("pid") == pid]
        if owned:
            return max(owned, key=lambda c: _title_score(c, hints))
    entry = (hints.get("desktopEntry") or "").strip().lower()
    ident = (hints.get("identity") or "").strip().lower()
    best, best_score = None, 0
    for c in usable:
        cls = ((c.get("class") or "") + " " + (c.get("initialClass") or "")).lower()
        score = _title_score(c, hints)
        if entry and entry in cls:
            score += 5
        if ident and ident in cls:
            score += 4
        if score > best_score:
            best, best_score = c, score
    return best


def _run(cmd, timeout=4):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


def focus_app(args):
    """Bring the window of a media app (an MPRIS player) to the front."""
    name = str(args.get("dbusName", ""))
    pid = 0
    if DBUS_NAME_RE.match(name):
        r = _run(["busctl", "--user", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                  "org.freedesktop.DBus", "GetConnectionUnixProcessID", "s", name])
        if r and r.returncode == 0:
            parts = r.stdout.split()
            if len(parts) == 2 and parts[1].isdigit():
                pid = int(parts[1])
    r = _run(["hyprctl", "clients", "-j"])
    if not r or r.returncode != 0:
        raise HelperError("could not read the window list", "no-compositor")
    try:
        clients = json.loads(r.stdout)
    except ValueError:
        raise HelperError("could not read the window list", "no-compositor")
    win = pick_window(clients, ancestors(pid) if pid else [], args)
    if not win:
        return {"ok": False}
    address = str(win.get("address", ""))
    if not ADDRESS_RE.match(address):
        return {"ok": False}
    r = _run(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:%s" })' % address])
    return {"ok": bool(r and r.returncode == 0), "title": win.get("title", ""), "class": win.get("class", "")}


# ── CLI ──────────────────────────────────────────────────────────────────────
def _out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    raw = sys.stdin.read(1 << 20) if not sys.stdin.isatty() else ""
    try:
        args = json.loads(raw) if raw.strip() else {}
        if not isinstance(args, dict):
            raise ValueError
    except ValueError:
        _out({"error": "bad request"})
        return 2
    try:
        if cmd == "sync":
            _out(sync(args))
        elif cmd == "cache":
            _out(read_json(os.path.join(state_dir(), "cache.json"), {"items": [], "errors": {}}))
        elif cmd == "settings-get":
            _out(settings_get())
        elif cmd == "settings-set":
            _out(settings_set(args))
        elif cmd == "alarms-sync":
            _out(with_ids(alarms_sync(args)["values"]))
        elif cmd == "import-nookisle":
            _out(import_nookisle(args))
        elif cmd == "ids":
            _out(sources_ids(args))
        elif cmd == "secret-set":
            _out(secret_store(str(args.get("id", "")), str(args.get("label", "")), str(args.get("password", ""))))
        elif cmd == "secret-clear":
            _out(secret_clear(str(args.get("id", ""))))
        elif cmd == "search-city":
            _out(search_city(args))
        elif cmd == "weather":
            _out(weather(args))
        elif cmd == "notify-due":
            _out(notify_due(args))
        elif cmd == "focus-app":
            _out(focus_app(args))
        elif cmd == "search-zones":
            _out(search_zones(args))
        elif cmd == "zones":
            _out(zones(args))
        else:
            _out({"error": "unknown command"})
            return 2
    except HelperError as e:
        _out({"error": str(e), "code": e.code})
        return 1
    return 0
