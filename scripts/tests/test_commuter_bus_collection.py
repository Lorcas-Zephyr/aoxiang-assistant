import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_FILE = REPO_ROOT / "ios" / "AoxiangApp" / "Sources" / "AoxiangApp" / "Resources" / "CommuterBusCollection.js"


class CommuterBusCollectionRuntimeTest(unittest.TestCase):
    def run_script(self, fail_tomorrow=False, stored_no=""):
        source = SCRIPT_FILE.read_text(encoding="utf-8")
        self.assertIn("__BUS_NO__", source)
        script = source.replace("__BUS_NO__", json.dumps("2020123456"))
        fixed_now = "2026-10-26T04:00:00.000Z"
        setup = f"""
const RealDate = Date;
class FixedDate extends RealDate {{
  constructor(...args) {{ super(...(args.length ? args : ["{fixed_now}"])); }}
  static now() {{ return new RealDate("{fixed_now}").getTime(); }}
}}
globalThis.Date = FixedDate;
globalThis.location = {{ hostname: "hq-bus.nwpu.edu.cn", pathname: "/h5/" }};
globalThis.localStorage = {{ getItem: () => {json.dumps(stored_no)}, removeItem: () => {{}} }};
const requests = [];
globalThis.fetch = async (url, options) => {{
  requests.push({{ url, options }});
  const body = new URLSearchParams(options.body);
  let data;
  if (url.includes("GetIcon")) data = {{ isSuccess: true, data: [] }};
  else if (url.includes("GetMyAppointment")) data = {{
    isSuccess: true,
    data: {{ list: [{{ yydh: "order-1", yyzt: "待核验", xlmc: "友谊到长安", ccrq: "2026/10/27", fcsj: "8:05" }}] }}
  }};
  else if (url.includes("GetRouteByType")) data = {{
    isSuccess: true,
    data: {{ filteredBusRoutes: [{{ Objid: "route-1", Name: "友谊到长安" }}], reservationDays: {{ TQYYXZTS: "2" }} }}
  }};
  else if (url.includes("GetReserveInfoList")) {{
    if ({str(fail_tomorrow).lower()} && body.get("rq") === "2026/10/27") {{
      return {{ ok: false, status: 503, json: async () => ({{}}) }};
    }}
    data = {{ isSuccess: true, data: [{{ objId: "trip-" + body.get("rq"), fcsj: "08:15", yyrs: "17", kyyrs: "20", sfkyy: true }}] }};
  }}
  return {{ ok: true, json: async () => data }};
}};
"""
        harness = f"""
{setup}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(JSON.stringify({{ value, requests }}))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "commuter-bus-runtime.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False, timeout=8)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        result["payload"] = json.loads(result["value"])
        return result

    def test_queries_routes_trips_and_both_appointment_filters_with_page_credentials(self):
        result = self.run_script()
        payload = result["payload"]
        self.assertEqual(payload["phase"], "bus_api_raw")
        self.assertTrue(payload["routesComplete"])
        self.assertTrue(payload["reservationsComplete"])
        self.assertTrue(payload["tripsComplete"])
        self.assertEqual(len(payload["reservations"]["data"]["list"]), 1)
        self.assertEqual(len(payload["tripGroups"]), 2)

        appointment_requests = [r for r in result["requests"] if "GetMyAppointment" in r["url"]]
        self.assertEqual([URLSearchParams(r["options"]["body"]).get("YYZT") for r in appointment_requests], ["待核验", ""])
        for request in result["requests"]:
            self.assertEqual(request["options"]["method"], "POST")
            self.assertEqual(request["options"]["credentials"], "include")
            self.assertEqual(request["options"]["cache"], "no-store")
            self.assertEqual(URLSearchParams(request["options"]["body"]).get("no"), "2020123456")

    def test_failed_trip_day_is_marked_partial_without_discarding_other_results(self):
        payload = self.run_script(fail_tomorrow=True)["payload"]
        self.assertTrue(payload["routesComplete"])
        self.assertTrue(payload["reservationsComplete"])
        self.assertFalse(payload["tripsComplete"])
        self.assertEqual(len(payload["tripGroups"]), 1)

    def test_current_education_identity_takes_priority_over_stale_bus_storage(self):
        result = self.run_script(stored_no="1999000000")
        self.assertEqual(result["payload"]["no"], "2020123456")
        for request in result["requests"]:
            self.assertEqual(URLSearchParams(request["options"]["body"]).get("no"), "2020123456")


class URLSearchParams:
    def __init__(self, value):
        from urllib.parse import parse_qs

        self.values = parse_qs(value, keep_blank_values=True)

    def get(self, key):
        values = self.values.get(key, [])
        return values[0] if values else None


if __name__ == "__main__":
    unittest.main()
