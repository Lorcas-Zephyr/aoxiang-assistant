(function (mode) {
  const allowNavigation = __ALLOW_NAV__;
  // 校车系统用 localStorage.NO 作为身份参数，首次进入时由原生层注入。
  const BUS_NO = __BUS_NO__;
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

  const collectGrades = async () => {
    const sheetHtml = await fetchText("/student/for-std/grade/sheet/");
    const studentId = extractStudentId(sheetHtml) || await fetchStudentId();
    if (!studentId) throw new Error("Student id unavailable");
    const semesters = extractSemesters(sheetHtml);
    // A small batch avoids overwhelming the portal. Track failures so a partial
    // transcript is never mistaken for a complete update by the caller.
    const gradeResponses = [];
    let failedSemesters = 0;
    for (let offset = 0; offset < semesters.length; offset += 4) {
      const batch = semesters.slice(offset, offset + 4).filter((semester) =>
        semester && semester.id);
      const responses = await Promise.all(batch.map(async (semester) => {
        try {
          return await fetchJson(
            "/student/for-std/grade/sheet/info/" + encodeURIComponent(studentId) +
            "?semester=" + encodeURIComponent(semester.id));
        } catch (ignored) {
          failedSemesters++;
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
      gradeResponses,
      gpaResponse,
      complete: failedSemesters === 0,
      failedSemesterCount: failedSemesters
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
    return { phase: "schedule_api_raw", semester, printData };
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
      return result("target_error", { target: mode, message: current.message || "接口读取失败" });
    }
    if (current && current.status === "loading") return result("api_waiting");
    const next = setState({ status: "loading", startedAt: Date.now() });
    collector().then((value) => {
      next.status = "done";
      next.result = value;
    }).catch((error) => {
      next.status = "error";
      next.message = String(error && error.message || error || "接口读取失败");
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
      ? result("electricity_api_raw", { response })
      : result("api_waiting");
  }

  // ---------------------------------------------------------------- bus --
  // 校车（后勤通勤车）H5：所有接口都是 POST + x-www-form-urlencoded，
  // 身份参数 no/GH 取自 localStorage.NO，可由原生层注入的 BUS_NO 兜底。
  // 详见 docs/HQ_BUS_API.md。

  const busIdentity = () => {
    let value = "";
    try {
      value = String(localStorage.getItem("NO") || "").trim();
    } catch (ignored) {}
    if (!value) value = String(BUS_NO == null ? "" : BUS_NO).trim();
    if (value) {
      try { localStorage.setItem("NO", value); } catch (ignored) {}
    }
    return value;
  };

  const busBody = (fields) => Object.keys(fields)
    .map((key) => encodeURIComponent(key) + "=" + encodeURIComponent(String(fields[key] == null ? "" : fields[key])))
    .join("&") + "&";

  const busPost = async (path, fields) => {
    const response = await fetchResponse(path, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json, text/plain, */*"
      },
      body: busBody(fields)
    });
    if (!response.ok) throw new Error("HTTP " + response.status + " " + path);
    return response.json();
  };

  const busDate = (date) =>
    date.getFullYear() + "/" + (date.getMonth() + 1) + "/" + date.getDate();

  const busIsoDate = (date) =>
    date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0") + "-" +
    String(date.getDate()).padStart(2, "0");

  const busItems = (response) => {
    const data = response && response.data;
    return Array.isArray(data) ? data : [];
  };

  const collectBus = async () => {
    const no = busIdentity();
    if (!no) throw new Error("校车身份参数缺失，请先在应用内打开一次校车页面");
    const today = new Date();
    const tomorrow = new Date(today.getTime() + 24 * 3600 * 1000);

    // 我的预约：「待核验」是页面默认筛选，再补一次不带状态的查询，
    // 以免审核中的记录被过滤掉。两次结果按内容去重。
    const reservations = [];
    const seen = new Set();
    for (const status of ["待核验", ""]) {
      let response;
      try {
        response = await busPost("/api/GetMyAppointment", { YYRGH: no, YYZT: status, no });
      } catch (ignored) {
        continue;
      }
      const data = response && response.data;
      const list = data && Array.isArray(data.list) ? data.list : [];
      list.forEach((item) => {
        const key = JSON.stringify(item);
        if (seen.has(key)) return;
        seen.add(key);
        reservations.push(item);
      });
    }

    let routesResponse = null;
    try {
      routesResponse = await busPost("/api/GetRouteByType", { type: "通勤车", no });
    } catch (ignored) {}
    const routes = routesResponse && routesResponse.data &&
      Array.isArray(routesResponse.data.filteredBusRoutes)
      ? routesResponse.data.filteredBusRoutes : [];

    // 只取今明两天的班次，避免把预约提醒变成批量扫描。
    const groups = [];
    for (const route of routes.slice(0, 4)) {
      for (const day of [today, tomorrow]) {
        let response;
        try {
          response = await busPost("/api/GetReserveInfoList", {
            rq: busDate(day),
            xllx: "通勤车",
            xlId: route.Objid,
            gh: no,
            no
          });
        } catch (ignored) {
          continue;
        }
        const items = busItems(response);
        if (!items.length) continue;
        groups.push({
          date: busIsoDate(day),
          routeId: route.Objid || "",
          routeName: route.Name || "",
          items
        });
      }
    }

    return {
      phase: "bus_api_raw",
      no,
      routes: routesResponse,
      reservations: { isSuccess: true, data: { list: reservations } },
      tripGroups: groups
    };
  };

  if (mode === "bus") {
    if (host !== "hq-bus.nwpu.edu.cn") return result("api_unavailable");
    if (!path.startsWith("/h5")) {
      if (!allowNavigation) return result("api_unavailable");
      location.replace(location.origin + "/h5/");
      return result("clicked", { clicked: "direct_api_bus" });
    }
    if (!document.querySelector("#app")) return result("api_waiting");
    return launch(collectBus);
  }

  return result("api_unavailable");
})("__MODE__");
