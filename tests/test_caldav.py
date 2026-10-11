"""CalDAV against a small local server: Basic auth, principal and calendar-home
discovery, a calendar listing, and an event REPORT. Run with the other tests:
python3 -I -B -m unittest discover tests"""
import base64
import datetime as dt
import http.server
import os
import sys
import tempfile
import threading
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import tidepool_helper as h  # noqa: E402

NS = 'xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"'


def multistatus(*responses):
    return ('<?xml version="1.0"?><d:multistatus %s>%s</d:multistatus>' % (NS, "".join(responses))).encode()


def response(href, props):
    return "<d:response><d:href>%s</d:href><d:propstat><d:prop>%s</d:prop></d:propstat></d:response>" % (href, props)


class FakeDav(http.server.BaseHTTPRequestHandler):
    ics = ""
    requests = []

    def log_message(self, *a):
        pass

    def do_PROPFIND(self):
        self.handle_dav()

    def do_REPORT(self):
        self.handle_dav()

    def handle_dav(self):
        want = "Basic " + base64.b64encode(b"me:s3cret").decode()
        if self.headers.get("Authorization") != want:
            self.send_response(401)
            self.end_headers()
            return
        length = int(self.headers.get("Content-Length") or 0)
        self.rfile.read(length)
        FakeDav.requests.append((self.command, self.path))
        path = self.path
        if self.command == "REPORT":
            body = multistatus(response(path + "ev1.ics", "<c:calendar-data>%s</c:calendar-data>" % FakeDav.ics))
        elif path == "/dav/":
            body = multistatus(response("/dav/", "<d:current-user-principal><d:href>/dav/principals/me/</d:href></d:current-user-principal>"))
        elif path == "/dav/principals/me/":
            body = multistatus(response(path, "<c:calendar-home-set><d:href>/dav/cal/</d:href></c:calendar-home-set>"))
        elif path == "/dav/cal/":
            body = multistatus(
                response("/dav/cal/", "<d:resourcetype><d:collection/></d:resourcetype>"),
                response("/dav/cal/work/", "<d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>Work</d:displayname>"),
                response("/dav/cal/inbox/", "<d:resourcetype><d:collection/></d:resourcetype>"))
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(207)
        self.send_header("Content-Type", "application/xml")
        self.end_headers()
        self.wfile.write(body)


class CalDavTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        os.environ["TIDEPOOL_STATE_DIR"] = os.path.join(self.tmp.name, "state")
        today = dt.date.today().strftime("%Y%m%d")
        FakeDav.ics = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:dav1\r\nSUMMARY:Planning\r\n"
                       "DTSTART:%sT140000\r\nDTEND:%sT150000\r\nLOCATION:HQ\r\n"
                       "DESCRIPTION:Join https://meet.google.com/abc-defg-hij\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n") % (today, today)
        FakeDav.requests = []
        self.srv = http.server.HTTPServer(("127.0.0.1", 0), FakeDav)
        threading.Thread(target=self.srv.serve_forever, daemon=True).start()
        self.base = "http://127.0.0.1:%d/dav/" % self.srv.server_port
        self._orig = h.secret_lookup

    def tearDown(self):
        h.secret_lookup = self._orig
        self.srv.shutdown()
        self.srv.server_close()
        self.tmp.cleanup()

    def test_discovers_calendars_and_reads_events(self):
        h.secret_lookup = lambda sid: "s3cret"
        r = h.sync({"sources": [{"kind": "caldav", "url": self.base, "user": "me", "label": "Dav"}]})
        self.assertEqual(r["errors"], {})
        self.assertEqual([i["title"] for i in r["items"]], ["Planning"])
        self.assertEqual(r["items"][0]["location"], "HQ")
        self.assertEqual(r["items"][0]["meetingUrl"], "https://meet.google.com/abc-defg-hij")
        self.assertIn(("REPORT", "/dav/cal/work/"), FakeDav.requests)            # only real calendars are queried
        self.assertNotIn(("REPORT", "/dav/cal/inbox/"), FakeDav.requests)

    def test_wrong_password_is_an_auth_error(self):
        h.secret_lookup = lambda sid: "nope"
        r = h.sync({"sources": [{"kind": "caldav", "url": self.base, "user": "me"}]})
        self.assertEqual(r["items"], [])
        self.assertEqual(list(r["errors"].values()), ["auth-error"])

    def test_missing_keyring_entry_is_an_auth_error(self):
        def none(sid):
            raise h.HelperError("no password stored", "auth-error")
        h.secret_lookup = none
        r = h.sync({"sources": [{"kind": "caldav", "url": self.base, "user": "me"}]})
        self.assertEqual(list(r["errors"].values()), ["auth-error"])


if __name__ == "__main__":
    unittest.main()
