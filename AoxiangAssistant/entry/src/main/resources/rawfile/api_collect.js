(function (mode) {
  const allowNavigation = __ALLOW_NAV__;
  const host = location.hostname;
  const path = location.pathname;
  const stateKey = "__aoxiangAssistantApiState_" + mode;

  const result = (phase, extra) => JSON.stringify(Object.assign({ phase }, extra || {}));
  const state = () => window[stateKey];
  const setState = (value) => {
    window[stateKey] = value;
    return value;
  };

  const FETCH_TIMEOUT_MS = 12000;

  const fetchResponse = async (url, options) => {
    const controller = typeof AbortController === "function" ? new AbortController() : null;
    const timer = controller ? setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS) : null;
    try {
      return await fetch(url, Object.assign({}, options || {}, {
        credentials: "include",
        cache: "no-store",
        signal: controller ? controller.signal : undefined
      }));
    } finally {
      if (timer) clearTimeout(timer);
    }
  };

  const fetchText = async (url) => {
    const response = await fetchResponse(url);
    if (!response.ok) throw new Error("HTTP " + response.status + " " + url);
    return response.text();
  };

  const fetchJson = async (url) => {
    const response = await fetchResponse(url, {
      headers: { Accept: "application/json" }
    });
    if (!response.ok) throw new Error("HTTP " + response.status + " " + url);
    return response.json();
  };

  const decodeJavascriptString = (value) => {
    const normalized = String(value || "").replace(/\\'/g, "'");
    return JSON.parse('"' + normalized + '"');
  };

  const extractSemesters = (html) => {
    const match = String(html || "").match(
      /(?:var|const|let)\s+semesters\s*=\s*JSON\.parse\(\s*'([\s\S]*?)'\s*\)/);
    if (!match) throw new Error("Semester data unavailable");
    const semesters = JSON.parse(decodeJavascriptString(match[1]));
    if (!Array.isArray(semesters) || !semesters.length) {
      throw new Error("No semester data");
    }
    return semesters;
  };

  const extractStudentId = (html) => {
    const source = String(html || "");
    const hidden = source.match(/id=["']studentId["'][^>]*value=["']([^"']+)["']/i) ||
      source.match(/value=["']([^"']+)["'][^>]*id=["']studentId["']/i);
    if (hidden && hidden[1]) return hidden[1];
    const variable = source.match(/(?:var|const|let)\s+studentId\s*=\s*["']?([^;"'\s]+)["']?\s*;/);
    return variable && variable[1] ? variable[1] : "";
  };

  const studentIdFromScheduleResources = () => {
    try {
      for (const entry of performance.getEntriesByType("resource").slice().reverse()) {
        const match = String(entry && entry.name || "").match(
          /\/for-std\/course-table\/semester\/[^/]+\/print-data\/([^/?#]+)/);
        if (match && match[1]) return decodeURIComponent(match[1]);
      }
    } catch (ignored) {}
    return "";
  };

  const studentIdFromCurrentPage = () => {
    const input = document.querySelector("#studentId");
    return String(window.studentId || input && input.value || "");
  };

  const waitForScheduleStudentId = () => new Promise((resolve) => {
    const deadline = Date.now() + 4000;
    const check = () => {
      const value = studentIdFromScheduleResources() || studentIdFromCurrentPage();
      if (value || Date.now() >= deadline) {
        resolve(value);
      } else {
        setTimeout(check, 200);
      }
    };
    check();
  });

  const fetchStudentId = async () => {
    const studentInfo = await fetchJson("/student/for-std/student-portrait/getStdInfo");
    return String(studentInfo && studentInfo.student && studentInfo.student.id || "");
  };

  const dateValue = (value) => /^\d{4}-\d{2}-\d{2}$/.test(String(value || ""))
    ? String(value) : "";

  const lastActivityDate = (semester, printData) => {
    const startDate = dateValue(semester && semester.startDate);
    if (!startDate) return "";
    const table = printData && printData.studentTableVm;
    const activities = table && Array.isArray(table.activities) ? table.activities : [];
    const start = new Date(startDate + "T00:00:00Z");
    let lastOffset = 13;
    activities.forEach((activity) => {
      const weekday = Number.parseInt(activity && activity.weekday, 10);
      if (weekday < 1 || weekday > 7) return;
      (Array.isArray(activity.weekIndexes) ? activity.weekIndexes : []).forEach((value) => {
        const week = Number.parseInt(value, 10);
        if (Number.isFinite(week) && week > 0) {
          lastOffset = Math.max(lastOffset, (week - 1) * 7 + weekday - 1);
        }
      });
    });
    start.setUTCDate(start.getUTCDate() + lastOffset);
    return start.toISOString().slice(0, 10);
  };

  const chooseInitialSemester = (semesters, today) => {
    const sorted = semesters.slice().filter((semester) =>
      semester && dateValue(semester.startDate)).sort((left, right) =>
      dateValue(left.startDate).localeCompare(dateValue(right.startDate)));
    if (!sorted.length) throw new Error("No dated semester");
    const containing = sorted.find((semester) => {
      const start = dateValue(semester.startDate);
      const end = dateValue(semester.endDate);
      return start <= today && (!end || today <= end);
    });
    if (containing) return { sorted, index: sorted.indexOf(containing) };
    const nextIndex = sorted.findIndex((semester) => dateValue(semester.startDate) > today);
    return { sorted, index: nextIndex >= 0 ? nextIndex : sorted.length - 1 };
  };

  // ---- JS 端数据转换（仿 PortalApiParsers） ----

  const DAY_LABELS = ["", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"];

  const firstNonEmpty = (...values) => {
    for (const value of values) {
      if (value != null && String(value).trim() !== "") return String(value).trim();
    }
    return "";
  };

  const gradeRows = (responses) => {
    const rows = [];
    (Array.isArray(responses) ? responses : []).forEach((response) => {
      if (!response || typeof response !== "object") return;
      const semesterGrades = response.semesterId2studentGrades;
      if (!semesterGrades || typeof semesterGrades !== "object") return;
      Object.keys(semesterGrades).forEach((semesterId) => {
        const grades = semesterGrades[semesterId];
        if (!Array.isArray(grades)) return;
        grades.forEach((grade) => {
          if (!grade || grade.published === false) return;
          const course = grade.course || {};
          const name = firstNonEmpty(course.nameZh, grade.lessonNameZh);
          if (!name) return;
          const credits = course.credits != null && isFinite(Number(course.credits)) ? Number(course.credits) : 0;
          const gp = grade.gp != null && grade.gp !== "" && isFinite(Number(grade.gp)) ? Number(grade.gp) : null;
          const row = [name, credits];
          row.push(gp);
          row.push(grade.gaGrade == null ? "" : String(grade.gaGrade));
          row.push(grade.gradeDetail == null ? "" : String(grade.gradeDetail));
          rows.push(row);
        });
      });
    });
    return rows;
  };

  const gpaKeys = ["gpa", "avggpa", "averagegpa", "studentgpa", "cumulativegpa",
    "gradepointaverage", "averagegradepoint", "平均绩点", "平均学分绩点", "累计平均学分绩点"];

  const parseGpaNumber = (raw) => {
    if (raw == null) return NaN;
    const text = String(raw);
    const match = text.match(/(?:^|[^0-9])(\d(?:\.\d{1,4})?)(?:[^0-9]|$)/);
    if (!match) return NaN;
    const value = Number(match[1]);
    return isFinite(value) && value >= 0 && value <= 5 ? value : NaN;
  };

  const findGpa = (value, depth) => {
    if (value == null || depth > 6) return NaN;
    if (Array.isArray(value)) {
      for (const item of value) {
        const candidate = findGpa(item, depth + 1);
        if (!isNaN(candidate)) return candidate;
      }
      return NaN;
    }
    if (typeof value === "object") {
      const keys = Object.keys(value);
      for (const key of keys) {
        const normalized = String(key).replace(/[\s_\-]/g, "").toLowerCase();
        if (gpaKeys.indexOf(normalized) >= 0) {
          const candidate = parseGpaNumber(value[key]);
          if (!isNaN(candidate)) return candidate;
        }
      }
      for (const key of keys) {
        const candidate = findGpa(value[key], depth + 1);
        if (!isNaN(candidate)) return candidate;
      }
    }
    return NaN;
  };

  const gpa = (response) => {
    if (!response || typeof response !== "object") return NaN;
    const rank = response.stdGpaRankDto;
    const direct = parseGpaNumber(rank && rank.gpa) || parseGpaNumber(rank && rank.avgGpa);
    if (!isNaN(direct)) return direct;
    const responseDirect = parseGpaNumber(response.gpa) || parseGpaNumber(response.avgGpa);
    if (!isNaN(responseDirect)) return responseDirect;
    return findGpa(response, 0);
  };

  const compactWeeks = (values) => {
    const unique = [];
    (Array.isArray(values) ? values : []).forEach((value) => {
      const number = Number(value);
      if (isFinite(number) && number > 0 && unique.indexOf(number) < 0) unique.push(number);
    });
    unique.sort((a, b) => a - b);
    if (!unique.length) return "1~17周";
    const ranges = [];
    for (let index = 0; index < unique.length;) {
      let end = unique[index];
      while (index + 1 < unique.length && unique[index + 1] === end + 1) {
        index++;
        end = unique[index];
      }
      ranges.push(unique[index] === end ? String(unique[index]) : unique[index] + "~" + end);
      index++;
    }
    return ranges.join(",") + "周";
  };

  const teacherNames = (teachers) => {
    const names = [];
    (Array.isArray(teachers) ? teachers : []).forEach((teacher) => {
      const name = teacher && typeof teacher === "object"
        ? firstNonEmpty(teacher.nameZh, teacher.name, teacher.teacherName)
        : String(teacher == null ? "" : teacher).trim();
      if (name && names.indexOf(name) < 0) names.push(name);
    });
    return names.join("、");
  };

  const joinUnique = (...values) => {
    const parts = [];
    values.forEach((value) => {
      if (value != null && String(value).trim() !== "" && parts.indexOf(String(value).trim()) < 0) {
        parts.push(String(value).trim());
      }
    });
    return parts.join(" ");
  };

  const containsOnline = (value) => value != null &&
    (String(value).indexOf("网课") >= 0 || String(value).indexOf("线上") >= 0 || String(value).indexOf("在线") >= 0);

  const schedulePayload = (semester, printData) => {
    const semesters = [];
    const courses = [];
    const table = printData && printData.studentTableVm || null;
    const activities = table && Array.isArray(table.activities) ? table.activities : [];

    const semesterId = firstNonEmpty(semester && semester.id, semester && semester.code, "current");
    const semesterName = firstNonEmpty(semester && semester.nameZh, semester && semester.name,
      semester && semester.code, "当前学期");
    const startDate = semester ? String(semester.startDate || "") : "";
    const effectiveEnd = lastActivityDate(semester, printData);
    const endDate = effectiveEnd || (semester ? String(semester.endDate || "") : "");

    const semesterItem = { name: semesterName, dataSemester: semesterId };
    if (startDate) semesterItem.startDate = startDate;
    if (endDate) semesterItem.endDate = endDate;
    semesters.push(semesterItem);

    activities.forEach((activity) => {
      if (!activity) return;
      const name = String(activity.courseName || "").trim();
      const weekday = Number.parseInt(activity.weekday, 10);
      const startUnit = Number.parseInt(activity.startUnit, 10);
      const endUnit = Number.parseInt(activity.endUnit, 10);
      if (!name || weekday < 1 || weekday > 7 || startUnit < 1 || endUnit < startUnit) return;
      const location = joinUnique(activity.campus, activity.building, activity.room);
      if (containsOnline(name) || containsOnline(location)) return;
      const course = { name, dataSemester: semesterId };
      const code = String(activity.courseCode || "");
      if (code) course.code = code;
      if (activity.credits != null && isFinite(Number(activity.credits))) course.credits = Number(activity.credits);
      const teacher = teacherNames(activity.teachers);
      if (teacher) course.teacher = teacher;
      course.scheduleText = compactWeeks(activity.weekIndexes) + " " + DAY_LABELS[weekday] + " " +
        startUnit + "-" + endUnit + "节";
      if (location) course.location = location;
      courses.push(course);
    });

    return { semesters, courses };
  };

  const electricityBalance = (response) => {
    const showData = response && response.map && response.map.showData || null;
    if (!showData || typeof showData !== "object") return NaN;
    const keys = ["当前剩余电量", "剩余电量", "电费余额", "剩余电费"];
    for (const key of keys) {
      if (Object.prototype.hasOwnProperty.call(showData, key) && showData[key] != null) {
        const value = parseElectricityNumber(String(showData[key]));
        if (!isNaN(value) && value >= 0 && value < 100000) return value;
      }
    }
    return NaN;
  };

  const parseElectricityNumber = (raw) => {
    const cleaned = String(raw == null ? "" : raw).replace(/[^0-9.\-]/g, "");
    return cleaned === "" ? NaN : Number(cleaned);
  };

  // ---- 采集器 ----

  const collectGrades = async () => {
    const sheetHtml = await fetchText("/student/for-std/grade/sheet/");
    const studentId = extractStudentId(sheetHtml) || await fetchStudentId();
    if (!studentId) throw new Error("Student id unavailable");
    const semesters = extractSemesters(sheetHtml);
    const gradeResponses = [];
    for (let offset = 0; offset < semesters.length; offset += 4) {
      const batch = semesters.slice(offset, offset + 4).filter((semester) =>
        semester && semester.id);
      const responses = await Promise.all(batch.map(async (semester) => {
        try {
          return await fetchJson(
            "/student/for-std/grade/sheet/info/" + encodeURIComponent(studentId) +
            "?semester=" + encodeURIComponent(semester.id));
        } catch (ignored) {
          return null;
        }
      }));
      responses.forEach((response) => {
        if (response) gradeResponses.push(response);
      });
    }
    if (!gradeResponses.length) throw new Error("No grade response");
    let gpaResponse = null;
    try {
      gpaResponse = await fetchJson(
        "/student/for-std/student-portrait/getMyGpa?studentAssoc=" + encodeURIComponent(studentId));
    } catch (ignored) {}
    return {
      phase: "grade_api_raw",
      rows: gradeRows(gradeResponses),
      gpa: gpa(gpaResponse)
    };
  };

  const collectSchedule = async () => {
    const pageHtml = await fetchText("/student/for-std/course-table");
    const studentId = extractStudentId(pageHtml) || await waitForScheduleStudentId() ||
      await fetchStudentId();
    if (!studentId) throw new Error("Student id unavailable");
    const choice = chooseInitialSemester(extractSemesters(pageHtml),
      new Date().toISOString().slice(0, 10));
    const today = new Date().toISOString().slice(0, 10);
    let index = choice.index;
    let semester;
    let printData;
    while (true) {
      semester = choice.sorted[index];
      try {
        semester = await fetchJson("/student/ws/semester/get/" + encodeURIComponent(semester.id));
      } catch (ignored) {}
      printData = await fetchJson(
        "/student/for-std/course-table/semester/" + encodeURIComponent(semester.id) +
        "/print-data/" + encodeURIComponent(studentId));
      const effectiveEnd = lastActivityDate(semester, printData);
      if (!effectiveEnd || today <= effectiveEnd || index >= choice.sorted.length - 1) break;
      index++;
    }
    return { phase: "schedule_api_raw", payload: schedulePayload(semester, printData) };
  };

  const electricityApiResponse = (rootVue) => {
    const queue = rootVue ? [rootVue] : [];
    const visited = new Set();
    while (queue.length && visited.size < 100) {
      const component = queue.shift();
      if (!component || visited.has(component)) continue;
      visited.add(component);
      const data = component.$data || {};
      const candidates = [
        component.aboutEleric && component.aboutEleric.electricInfo,
        data.aboutEleric && data.aboutEleric.electricInfo,
        component.electricInfo,
        data.electricInfo
      ];
      for (const showData of candidates) {
        if (showData && typeof showData === "object" &&
            Object.prototype.hasOwnProperty.call(showData, "当前剩余电量")) {
          return { map: { showData } };
        }
      }
      (component.$children || []).forEach((child) => queue.push(child));
    }
    return null;
  };

  const launch = (collector) => {
    const current = state();
    if (current && current.status === "done") return JSON.stringify(current.result);
    if (current && current.status === "error") {
      return result("target_error", { target: mode, message: current.message || "interface failed" });
    }
    if (current && current.status === "loading") return result("api_waiting");
    const next = setState({ status: "loading", startedAt: Date.now() });
    collector().then((value) => {
      next.status = "done";
      next.result = value;
    }).catch((error) => {
      next.status = "error";
      next.message = String(error && error.message || error || "interface failed");
    });
    return result("api_waiting");
  };

  if (mode === "grades" || mode === "schedule") {
    if (host !== "jwxt.nwpu.edu.cn") return result("api_unavailable");
    if (path === "/student/home" && allowNavigation) {
      location.replace(location.origin + (mode === "grades"
        ? "/student/for-std/grade/sheet/" : "/student/for-std/course-table"));
      return result("clicked", { clicked: "direct_api_" + mode });
    }
    const onTarget = mode === "grades"
      ? path.includes("/student/for-std/grade/sheet")
      : path.includes("/student/for-std/course-table");
    if (!onTarget) return result("api_unavailable");
    return launch(mode === "grades" ? collectGrades : collectSchedule);
  }

  if (mode === "electricity") {
    if (host !== "yktapp.nwpu.edu.cn") return result("api_unavailable");
    if (path.startsWith("/plat")) {
      const token = new URL(location.href).searchParams.get("synjones-auth") ||
        sessionStorage.getItem("access_token") || "";
      if (token && allowNavigation) {
        const target = location.origin + "/jfdt/charge/feeitem/toAppitem" +
          "?feeitemid=182&synjones-auth=" + encodeURIComponent(token) +
          "&appId=36&loginFrom=h5&type=app";
        location.replace(target);
        return result("clicked", { clicked: "direct_electricity_api" });
      }
      return result("api_unavailable");
    }
    if (!path.startsWith("/jfdt/")) return result("api_unavailable");
    const app = document.querySelector("#app");
    const vue = app && app.__vue__;
    const response = electricityApiResponse(vue);
    return response
      ? result("electricity_api_raw", { balance: electricityBalance(response) })
      : result("api_waiting");
  }

  return result("api_unavailable");
})("__MODE__");