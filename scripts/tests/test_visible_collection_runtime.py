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
    def test_education_script_accepts_data_semester_and_returns_sanitized_success(self):
        source = SOURCE_FILE.read_text(encoding="utf-8")
        match = re.search(
            r"private static let educationCollectionScript = #\"\"\"(.*?)\"\"\"#",
            source,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match)
        script = match.group(1)
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


if __name__ == "__main__":
    unittest.main()
