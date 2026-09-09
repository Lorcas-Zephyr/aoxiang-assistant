import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_FILE = (
    REPO_ROOT
    / "ios"
    / "AoxiangApp"
    / "Sources"
    / "AoxiangApp"
    / "VisibleAuthenticationWebView.swift"
)


class VisibleCollectionRuntimeTest(unittest.TestCase):
    def embedded_script(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        match = re.search(
            r"private static let educationCollectionScript = #\"\"\"(.*?)\"\"\"#",
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        return match.group(1)

    def test_education_script_accepts_data_semester_and_returns_sanitized_success(self):
        script = self.embedded_script()
        harness = f"""
const window = {{
  studentId: "student-fixture",
  semesters: [
    {{ dataSemester: "term-fixture", name: "2026 秋", startDate: "2026-08-31", endDate: "2027-01-10" }}
  ]
}};
const document = {{
  querySelector: () => null,
  body: {{ innerText: "" }}
}};
const performance = {{ getEntriesByType: () => [] }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = performance;
globalThis.fetch = async (url) => {{
  const path = String(url).split("?")[0];
  if (path === "/student/for-std/grade/sheet/") return response("<html></html>");
  if (path === "/student/for-std/grade/sheet/info/student-fixture") return response(JSON.stringify({{
    semesterId2studentGrades: {{ "term-fixture": [{{
      published: true,
      course: {{ nameZh: "软件工程", credits: 3 }},
      gp: 4,
      gaGrade: 95,
      gradeDetail: "期末成绩 95"
    }}] }}
  }}));
  if (path === "/student/for-std/student-portrait/getMyGpa") return response(JSON.stringify({{ gpa: 3.76 }}));
  if (path === "/student/for-std/course-table") return response("<html></html>");
  if (path === "/student/ws/semester/get/term-fixture") return response(JSON.stringify({{
    id: "term-fixture", name: "2026 秋", startDate: "2026-08-31", endDate: "2027-01-10"
  }}));
  if (path === "/student/for-std/course-table/semester/term-fixture/print-data/student-fixture") return response(JSON.stringify({{
    studentTableVm: {{ activities: [{{
      courseName: "软件工程", courseCode: "SE-101", credits: 3,
      weekday: 1, startUnit: 1, endUnit: 2, weekIndexes: [1, 2],
      teachers: [{{ nameZh: "张老师" }}], campus: "长安", building: "A", room: "101"
    }}] }}
  }}));
  return response("not found", 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}

async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-runtime.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(
                ["node", str(path)],
                capture_output=True,
                check=False,
            )
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "软件工程")
        self.assertEqual(result["schedule"]["semester"]["id"], "term-fixture")
        self.assertEqual(result["schedule"]["activities"][0]["teachers"], ["张老师"])

    def test_education_script_uses_rendered_grade_table_when_grade_api_has_no_semesters(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{
  querySelectorAll: selector => selector === 'td' ? cells(['数据结构', '3', '4.0', '96', '期末 96']) : [],
  querySelector: () => null
}};
const gradeTable = {{
  querySelectorAll: selector => {{
    if (selector === 'thead th') return cells(['课程名称', '学分', '绩点', '成绩', '成绩构成']);
    if (selector === 'tbody tr' || selector === 'tr') return [gradeRow];
    return [];
  }}
}};
const window = {{}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
const performance = {{ getEntriesByType: () => [] }};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = performance;
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') return response('<html><body>学生成绩</body></html>');
  if (path === '/student/for-std/student-portrait/getStdInfo') return response(JSON.stringify({{
    student: {{ id: 'student-fixture' }}
  }}));
  if (path.startsWith('/student/for-std/grade/sheet/info/')) return response('unavailable', 503);
  if (path === '/student/for-std/student-portrait/getMyGpa') return response(JSON.stringify({{ gpa: 3.88 }}));
  if (path === '/student/for-std/course-table') return response(`
    <script>var semesters = [{{"id":"term-fixture","name":"2026 秋","startDate":"2026-08-31","endDate":"2027-01-10"}}];</script>
  `);
  if (path === '/student/ws/semester/get/term-fixture') return response(JSON.stringify({{
    id: 'term-fixture', name: '2026 秋', startDate: '2026-08-31', endDate: '2027-01-10'
  }}));
  if (path === '/student/for-std/course-table/semester/term-fixture/print-data/student-fixture') return response(JSON.stringify({{
    studentTableVm: {{ activities: [] }}
  }}));
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}

async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-dom-fallback.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(
                ["node", str(path)],
                capture_output=True,
                check=False,
            )
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"], [{
            "course": "数据结构",
            "credits": 3,
            "point": 4,
            "score": 96,
            "category": "课程",
            "detail": "期末 96",
        }])
        self.assertEqual(result["schedule"]["semester"]["id"], "term-fixture")

    def test_education_script_keeps_rendered_grade_table_when_grade_page_request_fails(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['离线成绩', '2', '3.5', '88', '平时 40 / 期末 48']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
globalThis.window = {{}};
globalThis.document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') throw new Error('grade page request unavailable');
  if (path === '/student/for-std/student-portrait/getStdInfo') return response(JSON.stringify({{ student: {{ id: 'student-fixture' }} }}));
  if (path.startsWith('/student/for-std/grade/sheet/info/')) return response('unavailable', 503);
  if (path === '/student/for-std/course-table') return response('<script>var semesters = [{{"id":"term-fixture","name":"2026 秋","startDate":"2026-08-31","endDate":"2027-01-10"}}];</script>');
  if (path === '/student/ws/semester/get/term-fixture') return response(JSON.stringify({{ id: 'term-fixture', name: '2026 秋', startDate: '2026-08-31', endDate: '2027-01-10' }}));
  if (path === '/student/for-std/course-table/semester/term-fixture/print-data/student-fixture') return response(JSON.stringify({{ studentTableVm: {{ activities: [] }} }}));
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-dom-fetch-fallback.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "离线成绩")

    def test_education_script_reads_same_origin_grade_table_inside_iframe(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['iframe成绩', '3', '4.0', '95', '期末 95']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const frameDocument = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
const frameWindow = {{ document: frameDocument }};
const frame = {{ contentWindow: frameWindow, contentDocument: frameDocument }};
const topDocument = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'iframe' ? [frame] : [],
  body: {{ innerText: '成绩页面' }}
}};
const window = {{ studentId: 'student-fixture', document: topDocument }};
globalThis.window = window;
globalThis.document = topDocument;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') return response('<html><body>成绩页面</body></html>');
  if (path === '/student/for-std/student-portrait/getMyGpa') return response(JSON.stringify({{ gpa: 3.9 }}));
  if (path === '/student/for-std/course-table') return response('<script>var semesters = [{{"id":"term-fixture","name":"2026 秋","startDate":"2026-08-31","endDate":"2027-01-10"}}];</script>');
  if (path === '/student/ws/semester/get/term-fixture') return response(JSON.stringify({{ id: 'term-fixture', name: '2026 秋', startDate: '2026-08-31', endDate: '2027-01-10' }}));
  if (path === '/student/for-std/course-table/semester/term-fixture/print-data/student-fixture') return response(JSON.stringify({{ studentTableVm: {{ activities: [] }} }}));
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-iframe-fallback.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "iframe成绩")

    def test_education_script_waits_for_delayed_grade_table_rendering(self):
        script = self.embedded_script()
        harness = f"""
let rendered = false;
setTimeout(() => {{ rendered = true; }}, 1800);
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['延迟成绩', '2', '3.2', '87', '期末 87']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const window = {{ studentId: 'student-fixture' }};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' && rendered ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') return response('<html><body>学生成绩</body></html>');
  if (path === '/student/for-std/student-portrait/getMyGpa') return response(JSON.stringify({{ gpa: 3.2 }}));
  if (path === '/student/for-std/course-table') return response('<script>var semesters = [{{"id":"term-fixture","name":"2026 秋","startDate":"2026-08-31","endDate":"2027-01-10"}}];</script>');
  if (path === '/student/ws/semester/get/term-fixture') return response(JSON.stringify({{ id: 'term-fixture', name: '2026 秋', startDate: '2026-08-31', endDate: '2027-01-10' }}));
  if (path === '/student/for-std/course-table/semester/term-fixture/print-data/student-fixture') return response(JSON.stringify({{ studentTableVm: {{ activities: [] }} }}));
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-delayed-table.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "延迟成绩")

    def test_education_script_keeps_grades_when_schedule_endpoint_is_unavailable(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['仅成绩', '2', '3.5', '88', '期末 88']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const window = {{ studentId: 'student-fixture' }};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  body: {{ innerText: '学生成绩' }}
}};
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/grade/sheet/') return response('<html><body>学生成绩</body></html>');
  if (path === '/student/for-std/course-table') throw new Error('schedule endpoint unavailable');
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(String(value))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-grade-only.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        result = json.loads(stdout)
        self.assertEqual(result["phase"], "success")
        self.assertEqual(result["grades"][0]["course"], "仅成绩")
        self.assertEqual(result["schedule"]["semester"]["id"], "current")
        self.assertFalse(result["scheduleAvailable"])

    def test_education_script_returns_rendered_grades_without_student_bootstrap(self):
        script = self.embedded_script()
        harness = f"""
const cells = values => values.map(value => ({{ innerText: value, textContent: value }}));
const gradeRow = {{ querySelectorAll: selector => selector === 'td' ? cells(['无学号成绩', '2', '3.1', '86', '期末 86']) : [] }};
const gradeTable = {{
  querySelectorAll: selector => selector === 'thead th'
    ? cells(['课程名称', '学分', '绩点', '成绩', '成绩构成'])
    : (selector === 'tbody tr' || selector === 'tr' ? [gradeRow] : [])
}};
const document = {{
  querySelector: () => null,
  querySelectorAll: selector => selector === 'table' ? [gradeTable] : [],
  documentElement: {{ outerHTML: '<html><body>学生成绩</body></html>' }},
  body: {{ innerText: '学生成绩' }}
}};
const window = {{ document }};
let studentInfoCalls = 0;
globalThis.window = window;
globalThis.document = document;
globalThis.performance = {{ getEntriesByType: () => [] }};
globalThis.fetch = async (url) => {{
  const path = String(url).split('?')[0];
  if (path === '/student/for-std/student-portrait/getStdInfo') {{
    studentInfoCalls += 1;
    return response('unavailable', 503);
  }}
  return response('not found', 404);
}};
function response(body, status = 200) {{
  return {{ status, ok: status >= 200 && status < 300, text: async () => body }};
}}
async function execute() {{
{script}
}}
execute().then(value => process.stdout.write(JSON.stringify({{ result: JSON.parse(value), studentInfoCalls }}))).catch(error => {{
  process.stderr.write(String(error && error.stack || error));
  process.exit(1);
}});
"""
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "education-rendered-no-bootstrap.js"
            path.write_text(harness, encoding="utf-8")
            completed = subprocess.run(["node", str(path)], capture_output=True, check=False)
        stdout = completed.stdout.decode("utf-8", errors="replace")
        stderr = completed.stderr.decode("utf-8", errors="replace")
        self.assertEqual(completed.returncode, 0, stderr or stdout)
        payload = json.loads(stdout)
        self.assertLessEqual(payload["studentInfoCalls"], 1)
        self.assertEqual(payload["result"]["phase"], "success")
        self.assertEqual(payload["result"]["grades"][0]["course"], "无学号成绩")
        self.assertFalse(payload["result"]["scheduleAvailable"])


if __name__ == "__main__":
    unittest.main()
