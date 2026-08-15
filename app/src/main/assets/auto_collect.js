(function (mode) {
  const allowNavigation = __ALLOW_NAV__;
  const username = __USERNAME__;
  const password = __PASSWORD__;
  const smsCode = __SMS_CODE__;
  const canAutofill = __CAN_AUTOFILL__;
  const canFillSms = __CAN_FILL_SMS__;

  const text = (value) => (value || "").replace(/\s+/g, " ").trim();
  const visible = (element) => {
    try {
      const style = getComputedStyle(element);
      return style.display !== "none" && style.visibility !== "hidden" && element.getClientRects().length > 0;
    } catch (ignored) {
      return false;
    }
  };

  const documents = [];
  const collectDocuments = (currentWindow) => {
    try {
      const currentDocument = currentWindow.document;
      if (!currentDocument || documents.includes(currentDocument)) return;
      documents.push(currentDocument);
      [...currentDocument.querySelectorAll("iframe")].forEach((frame) => {
        try {
          if (frame.contentWindow && frame.contentDocument) collectDocuments(frame.contentWindow);
        } catch (ignored) {
          // Cross-origin frames are intentionally skipped.
        }
      });
    } catch (ignored) {
      // The top-level page remains available even if a child frame is cross-origin.
    }
  };
  collectDocuments(window);

  const body = text(documents.map((doc) => (doc.body ? doc.body.innerText : "")).join(" "));
  const host = location.hostname;

  const setValue = (input, value) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
    input.dispatchEvent(new Event("blur", { bubbles: true }));
  };

  const clickElement = (element) => {
    try {
      element.scrollIntoView({ block: "center", inline: "center" });
    } catch (ignored) {}
    try {
      element.click();
      return true;
    } catch (ignored) {}
    try {
      element.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
      return true;
    } catch (ignored) {}
    return false;
  };

  const findButton = (doc, pattern) => [...doc.querySelectorAll("button, input[type=submit], input[type=button]")]
    .find((element) => visible(element) && pattern.test(text(element.innerText || element.value)));

  const clickLeaf = (patterns) => {
    for (const pattern of patterns) {
      for (const doc of documents) {
        const leaf = [...doc.querySelectorAll("a, button, [role=button], li, body *")].find((candidate) =>
          candidate.children.length === 0 &&
          pattern.test(text(candidate.innerText || candidate.textContent || candidate.value || "")));
        if (!leaf) continue;
        const target = leaf.closest("a, button, [role=button], li, .menu-item, .van-grid-item__content, .van-grid-item, .weui-grid") || leaf;
        if (clickElement(target)) return text(leaf.innerText || leaf.textContent || leaf.value || "");
      }
    }
    return "";
  };

  // The card platform has its own password form. Always choose the university
  // SSO entry before allowing the shared credentials to be filled.
  if (mode === "electricity" && host === "yktapp.nwpu.edu.cn" && allowNavigation) {
    if (location.pathname.startsWith("/plat") && location.pathname !== "/plat/login" &&
        /账户余额/.test(body) && !/(?:^|\s)请登录(?:\s|$)/.test(body)) {
      const auth = new URL(location.href).searchParams.get("synjones-auth");
      if (auth) {
        const redirect = "https://yktapp.nwpu.edu.cn/berserker-base/redirect" +
          "?appId=36&type=app&synjones-auth=" + encodeURIComponent(auth) + "&loginFrom=h5";
        location.replace(redirect);
      }
      return JSON.stringify({ phase: "clicked", clicked: "electricity_page" });
    }
    const clicked = clickLeaf([/统一身份认证/, /^统一登录$/, /^更多登录方式$/]);
    if (clicked) return JSON.stringify({ phase: "clicked", clicked });
  }

  const loginDocument = documents.find((doc) => doc.querySelector('input[type="password"]') ||
    (doc.querySelector("input") && /账号密码|密码登录|统一认证/.test(text(doc.body ? doc.body.innerText : ""))));
  if (loginDocument && !(mode === "electricity" && host === "yktapp.nwpu.edu.cn")) {
    const loginBody = text(loginDocument.body ? loginDocument.body.innerText : "");
    const passwordTab = [...loginDocument.querySelectorAll("body *")].find((element) =>
      element.children.length === 0 && visible(element) && /^(账号密码|密码登录|User-Password)$/i.test(text(element.innerText)));
    if (passwordTab) clickElement(passwordTab);
    const passwordInput = [...loginDocument.querySelectorAll('input[type="password"]')].find(visible);
    const smsField = [...loginDocument.querySelectorAll("input")].find((input) => {
      const descriptor = text([input.name, input.id, input.placeholder, input.type].join(" "));
      return visible(input) && input !== passwordInput && /sms|message|verify|code|验证码|动态码/.test(descriptor);
    });
    const asksForSms = /短信|手机验证码|动态验证码/.test(loginBody) && smsField;
    if (/验证码(?:错误|不正确|无效|已失效)|动态码(?:错误|不正确|无效|已失效)|校验码(?:错误|不正确|无效|已失效)/.test(loginBody)) {
      return JSON.stringify({ phase: "sms_error", rows: [] });
    }
    if (asksForSms) {
      if (canFillSms && smsCode) {
        setValue(smsField, smsCode);
        const submit = findButton(loginDocument, /验证|确认|提交|登录/);
        if (submit) clickElement(submit);
        return JSON.stringify({ phase: "sms_submitting", rows: [] });
      }
      return JSON.stringify({ phase: "sms_required", rows: [] });
    }
    const usernameInput = [...loginDocument.querySelectorAll('input[name="username"], #username, input[type="text"], input[type="tel"], input[type="email"]')]
      .find((input) => visible(input) && input !== passwordInput);
    if (canAutofill && username && password && usernameInput && passwordInput) {
      setValue(usernameInput, username);
      setValue(passwordInput, password);
      const submit = findButton(loginDocument, /登录|login|提交/i);
      if (submit) clickElement(submit);
      return JSON.stringify({ phase: "credentials_submitting", rows: [] });
    }
    if (/密码(?:错误|不正确|无效)|账号或密码|用户名或密码|登录失败|认证失败/.test(loginBody)) {
      return JSON.stringify({ phase: "credentials_error", rows: [] });
    }
    return JSON.stringify({ phase: "credentials_required", rows: [] });
  }

  if (mode === "validate" && host === "jwxt.nwpu.edu.cn" &&
      !location.pathname.includes("sso-login")) {
    return JSON.stringify({ phase: "credentials_valid", rows: [] });
  }

  if ((mode === "grades" || mode === "schedule") && host === "jwxt.nwpu.edu.cn") {
    const directPath = mode === "schedule"
      ? "/student/for-std/course-table"
      : "/student/for-std/grade/sheet/";
    const directKey = "campus_direct_" + mode;
    if (location.pathname === "/student/home" && !sessionStorage.getItem(directKey)) {
      sessionStorage.setItem(directKey, "1");
      location.replace(location.origin + directPath);
      return JSON.stringify({ phase: "clicked", clicked: "direct_" + mode });
    }
    const failedDirect = location.pathname !== "/student/home" &&
      /无权限|没有权限|页面不存在|访问受限|404|not found/i.test(body);
    if (failedDirect) {
      location.replace(location.origin + "/student/home");
      return JSON.stringify({ phase: "clicked", clicked: "education_home" });
    }
  }

  if (mode === "electricity") {
    const onElectricityPage = host === "yktapp.nwpu.edu.cn" && location.pathname.startsWith("/jfdt/");
    if (onElectricityPage) {
      const parseElectricityValue = (value) => {
        const match = String(value == null ? "" : value).match(/-?\d+(?:\.\d+)?/);
        const parsed = match ? Number.parseFloat(match[0]) : Number.NaN;
        return Number.isFinite(parsed) && parsed >= 0 && parsed < 100000 ? parsed : null;
      };
      const electricityLabels = [
        "剩余电费", "电费余额", "剩余金额", "当前剩余电量", "剩余电量", "电量余额"
      ];
      const valueFromInfo = (info) => {
        if (!info || typeof info !== "object") return null;
        for (const label of electricityLabels) {
          if (!Object.prototype.hasOwnProperty.call(info, label)) continue;
          const parsed = parseElectricityValue(info[label]);
          if (parsed !== null) return parsed;
        }
        for (const [label, value] of Object.entries(info)) {
          if (!/(?:剩余.*(?:电费|金额|电量)|(?:电费|电量).*余额)/.test(text(label))) continue;
          const parsed = parseElectricityValue(value);
          if (parsed !== null) return parsed;
        }
        return null;
      };

      // The electricity page keeps the current balance in a Vue component and
      // does not attach a currency/unit suffix to the rendered value.
      const app = document.querySelector("#app");
      const rootVue = app && app.__vue__;
      const components = rootVue ? [rootVue] : [];
      const visited = new Set();
      while (components.length) {
        const component = components.shift();
        if (!component || visited.has(component)) continue;
        visited.add(component);
        const data = component.$data || {};
        const candidates = [
          component.aboutEleric && component.aboutEleric.electricInfo,
          data.aboutEleric && data.aboutEleric.electricInfo,
          component.electricInfo,
          data.electricInfo
        ];
        for (const candidate of candidates) {
          const balance = valueFromInfo(candidate);
          if (balance !== null) return JSON.stringify({ phase: "electricity_data", balance });
        }
        (component.$children || []).forEach((child) => components.push(child));
      }

      const electricityContexts = documents.flatMap((doc) => [...doc.querySelectorAll("body *")])
        .filter((element) => {
          const own = text(element.innerText || element.textContent);
          return own.length > 0 && own.length < 240 &&
            /(?:剩余电费|电费余额|剩余金额|当前剩余电量|剩余电量|电量余额)/.test(own) &&
            /\d+(?:\.\d+)?/.test(own);
        });
      for (const element of electricityContexts) {
        const compact = text(element.innerText || element.textContent);
        const direct = compact.match(/(?:当前剩余电量|剩余电量|电量余额)\s*[：:]\s*(-?\d+(?:\.\d+)?)/) ||
          compact.match(/(?:剩余电费|电费余额|剩余金额)\s*[：:]?\s*(?:¥|￥)?\s*(-?\d+(?:\.\d+)?)\s*元/) ||
          compact.match(/(?:¥|￥)?\s*(-?\d+(?:\.\d+)?)\s*(?:元|度)\s*[：:]?\s*(?:剩余电费|电费余额|剩余金额|当前剩余电量|剩余电量|电量余额)/);
        if (direct) {
          const balance = Number.parseFloat(direct[1]);
          if (Number.isFinite(balance) && balance >= 0 && balance < 100000) {
            return JSON.stringify({ phase: "electricity_data", balance });
          }
        }
      }
    }

    return JSON.stringify({ phase: "waiting", body: body.slice(0, 1000), rows: [] });
  }

  const tables = documents.flatMap((doc) => [...doc.querySelectorAll("table")]).map((table) => {
    const headers = [...table.querySelectorAll("thead th")].map((cell) => text(cell.innerText));
    if (!headers.length) {
      table.querySelectorAll("tr:first-child th").forEach((cell) => headers.push(text(cell.innerText)));
    }
    const bodyRows = table.querySelectorAll("tbody tr");
    const sourceRows = bodyRows.length ? bodyRows : table.querySelectorAll("tr");
    const rows = [...sourceRows].map((row) => {
      const cells = [...row.querySelectorAll("td")].map((cell) => text(cell.innerText));
      const courseName = row.querySelector(".course-name");
      if (courseName && cells.length) cells[0] = text(courseName.innerText);
      return cells;
    }).filter((row) => row.length && row.some(Boolean));
    return { headers, rows };
  }).filter((table) => table.rows.length);

  const gradeRows = [];
  tables.forEach((table) => table.rows.forEach((row) => {
    const credit = Number.parseFloat(row[1]);
    const point = Number.parseFloat(row[2]);
    const score = Number.parseFloat(row[3]);
    const passFail = /^(P|NP|通过|不通过|优秀|良好|中等|及格|不及格)$/i.test(row[3] || "");
    if (row.length >= 4 && row[0] && Number.isFinite(credit) &&
        (Number.isFinite(point) || Number.isFinite(score) || passFail)) {
      gradeRows.push(row);
    }
  }));

  const onGradePage = host === "jwxt.nwpu.edu.cn" && documents.some((doc) =>
    (doc.location && doc.location.pathname.includes("/for-std/grade/sheet")) ||
    text(doc.body ? doc.body.innerText : "").includes("学生成绩"));
  if (onGradePage && gradeRows.length) return JSON.stringify({ phase: "data", rows: gradeRows });
  if (onGradePage) return JSON.stringify({ phase: "page", rows: [] });

  const semesterValuePattern = /\d{4}-\d{4}-\d+/;
  const scheduleTextPattern = /(周[一二三四五六日天]|星期[一二三四五六日天]).{0,20}第.{0,12}节|第.{0,12}节.{0,20}(周[一二三四五六日天]|星期[一二三四五六日天])/;
  const weekRangePattern = /(第?[一二三四五六七八九十百0-9]+周)|(\d{1,2}\s*[~至\-—]\s*\d{1,2}\s*周)|(单周|双周)/;
  const locationPattern = /(校区|教学楼|实验楼|楼|教室|室|A\s*\d|B\s*\d|C\s*\d|D\s*\d|E\s*\d|F\s*\d|G\s*\d|H\s*\d|S\s*\d|T\s*\d|U\s*\d)/i;
  const onlinePattern = /网课|线上|在线/;

  const looksLikeScheduleText = (value) => {
    const compact = text(value);
    return !!compact && (scheduleTextPattern.test(compact) || (weekRangePattern.test(compact) && compact.includes("节")));
  };

  const looksLikeLocation = (value) => {
    const compact = text(value);
    return !!compact && locationPattern.test(compact);
  };

  const toMaybeNumber = (value) => {
    const parsed = Number.parseFloat(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  };

  const uniquePush = (target, seen, course) => {
    const key = [
      course.dataSemester || "",
      course.name || "",
      course.code || "",
      course.scheduleText || "",
      course.teacher || "",
      course.location || ""
    ].join("|");
    if (!seen.has(key)) {
      seen.add(key);
      target.push(course);
    }
  };

  const dayLabels = ["", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"];

  const courseNameText = (element) => {
    const copy = element.cloneNode(true);
    copy.querySelectorAll(".tag-info, .label, .badge").forEach((tag) => tag.remove());
    return text(copy.textContent);
  };

  const textWithLineBreaks = (node) => {
    if (!node) return "";
    if (node.nodeType === 3) return node.nodeValue || "";
    if (node.nodeType !== 1) return "";
    const tag = (node.tagName || "").toUpperCase();
    if (tag === "BR") return "\n";
    const blockTags = new Set(["DIV", "P", "LI", "TR", "SECTION", "ARTICLE"]);
    const content = [...node.childNodes].map(textWithLineBreaks).join("");
    return blockTags.has(tag) ? `\n${content}\n` : content;
  };

  const splitCourseBlocks = (container) => {
    const blocks = [];
    let current = null;
    [...container.childNodes].forEach((node) => {
      const isCourseName = node.nodeType === Node.ELEMENT_NODE && node.classList.contains("course-name");
      if (isCourseName) {
        if (current) blocks.push(current);
        current = { name: courseNameText(node), nodes: [node] };
      } else if (current) {
        current.nodes.push(node);
      }
    });
    if (current) blocks.push(current);
    return blocks.map((block) => {
      const rawContent = block.nodes.map(textWithLineBreaks).join("");
      return {
        name: block.name,
        content: text(rawContent),
        lines: rawContent.split(/[\r\n]+/).map(text).filter(Boolean),
        nodes: block.nodes
      };
    }).filter((block) => block.name && block.content);
  };

  const scheduleTextFromBlock = (content, day) => {
    const parts = [];
    const pattern = /[（(]([^()（）]{1,40}?周(?:\s*[单双])?)[）)]\s*[（(]([^()（）]{1,20}?节)[）)]/g;
    let match;
    while ((match = pattern.exec(content)) !== null) {
      parts.push(`${text(match[1])} ${dayLabels[day]} ${text(match[2])}`);
    }
    return parts.length ? parts.join("; ") : `${dayLabels[day]} ${content}`;
  };

  const locationFromBlock = (content) => {
    const match = content.match(/(?:长安|友谊|太仓)校区\s+(?:教师另行安排场地[（(]?[^）)]*[）)]?|[^\s()（）]+)/);
    return match ? text(match[0]) : "";
  };

  const normalizeTeacher = (value) => text(value)
    .replace(/^(?:授课教师|任课教师|上课教师|教师|老师)\s*[：:]?\s*/, "")
    .replace(/\s*[|｜/]\s*/g, "、")
    .replace(/^[,，、\s]+|[,，、\s]+$/g, "");

  const validTeacher = (value) => {
    const candidate = normalizeTeacher(value);
    if (!candidate || candidate.length > 80 || /\d/.test(candidate)) return "";
    if (/(?:校区|教学楼|实验楼|教室|体育馆|操场|训练场|中心|课程|点击|查看|详情|另行安排|场地|第.+节|单周|双周|学科基础|专业基础|专业核心|公共基础|通识教育|实践实训|集中实践|创新创业|素质拓展|全校|本科|研究生|培养方案|课程类别|必修|选修|限选|任选)/.test(candidate)) return "";
    return /^[\u3400-\u9fffA-Za-z·.\s、,，]+$/.test(candidate) ? candidate : "";
  };

  const appendTeachers = (target, value) => {
    normalizeTeacher(value).split(/[\s、,，;；/|｜]+/).forEach((part) => {
      const candidate = validTeacher(part);
      if (candidate && !target.includes(candidate) && target.length < 15) target.push(candidate);
    });
  };

  const teacherFromBlock = (block, code, locationText) => {
    const teachers = [];
    const teacherSelector = [
      "[data-teacher]", "[data-teacher-name]", "[data-instructor]",
      ".teacher", ".teacher-name", ".course-teacher",
      "[class*='teacher']", "[class*='instructor']", "a[href*='teacher']",
      "[title*='教师']", "[title*='老师']"
    ].join(",");
    for (const node of block.nodes || []) {
      if (!node || node.nodeType !== 1) continue;
      const matches = [];
      if (node.matches && node.matches(teacherSelector)) matches.push(node);
      if (node.querySelectorAll) matches.push(...node.querySelectorAll(teacherSelector));
      for (const element of matches) {
        const raw = element.getAttribute("data-teacher") ||
          element.getAttribute("data-teacher-name") ||
          element.getAttribute("data-instructor") ||
          element.getAttribute("title") ||
          element.innerText || element.textContent || "";
        appendTeachers(teachers, raw);
      }
    }
    if (teachers.length) return teachers.join("、");

    const labelledPattern = /(?:授课教师|任课教师|上课教师|教师|老师)\s*[：:]\s*([\u3400-\u9fffA-Za-z·.]+(?:\s*(?:[,，、/;；]|\s)\s*[\u3400-\u9fffA-Za-z·.]+)*)/g;
    for (const labelled of block.content.matchAll(labelledPattern)) {
      appendTeachers(teachers, labelled[1]);
    }
    if (teachers.length) return teachers.join("、");

    let remainder = block.content;
    [block.name, code, locationText].filter(Boolean).forEach((part) => {
      remainder = remainder.split(part).join(" ");
    });
    remainder = remainder
      .replace(/\b[A-Za-z][A-Za-z0-9]*\d[A-Za-z0-9]*\.\d+\b/g, " ")
      .replace(/[（(][^()（）]{1,40}?周(?:\s*[单双])?[）)]/g, " ")
      .replace(/[（(][^()（）]{1,20}?节[）)]/g, " ")
      .replace(/(?:考试|考查|考察|PnP|必修|选修)/gi, " ");
    remainder.split(/\s+/)
      .map(validTeacher)
      .filter((value) => value && /^[\u3400-\u9fff·]{2,12}(?:[、,，][\u3400-\u9fff·]{2,12})*$/.test(value))
      .forEach((value) => appendTeachers(teachers, value));
    return teachers.join("、");
  };

  const scheduleRecordStart = /[（(]\s*[^()（）]{1,60}?周(?:\s*[单双])?\s*[）)]\s*[（(]\s*[^()（）]{1,20}?节\s*[）)]/g;

  const splitScheduleRecordLines = (block) => {
    const records = [];
    (block.lines || []).forEach((line) => {
      const starts = [];
      scheduleRecordStart.lastIndex = 0;
      let match;
      while ((match = scheduleRecordStart.exec(line)) !== null) starts.push(match.index);
      starts.forEach((start, index) => {
        records.push(line.slice(start, index + 1 < starts.length ? starts[index + 1] : line.length));
      });
    });
    if (records.length) return records;

    const flattened = block.content || "";
    const starts = [];
    scheduleRecordStart.lastIndex = 0;
    let match;
    while ((match = scheduleRecordStart.exec(flattened)) !== null) starts.push(match.index);
    starts.forEach((start, index) => {
      records.push(flattened.slice(start, index + 1 < starts.length ? starts[index + 1] : flattened.length));
    });
    return records;
  };

  const scheduleRecordsFromBlock = (block, day) => {
    const pattern = /^\s*[（(]\s*([^()（）]{1,60}?周(?:\s*[单双])?)\s*[）)]\s*[（(]\s*([^()（）]{1,20}?节)\s*[）)]\s*(.*?)\s*$/;
    const records = [];
    splitScheduleRecordLines(block).forEach((line) => {
      const match = line.match(pattern);
      if (!match) return;
      const remainder = text(match[3].replace(/\s+\d{1,3}院\s+.*$/, ""));
      const parts = remainder.split(/\s+/).filter(Boolean);
      const teacherParts = [];
      const teachers = [];
      while (parts.length) {
        const teacher = validTeacher(parts[parts.length - 1]);
        if (!teacher) break;
        parts.pop();
        teacherParts.unshift(teacher);
      }
      teacherParts.forEach((teacher) => appendTeachers(teachers, teacher));
      const location = text(parts.join(" "));
      if (!teachers.length || !location || !looksLikeLocation(location)) return;
      records.push({
        scheduleText: `${text(match[1])} ${dayLabels[day]} ${text(match[2])}`,
        teacher: teachers.join("、"),
        location
      });
    });
    return records;
  };

  const extractSchedulePayload = () => {
    const semesters = [];
    const seenSemesters = new Set();

    documents.forEach((doc) => {
      [...doc.querySelectorAll("select option")].forEach((option) => {
        const name = text(option.textContent);
        const value = text(option.value || option.getAttribute("value"));
        if (!name) return;
        if (!semesterValuePattern.test(value) && !/(学期|春|秋|夏|冬|\d{4}-\d{4})/.test(name)) return;
        const dataSemester = value || name;
        const key = dataSemester + "|" + name;
        if (seenSemesters.has(key)) return;
        seenSemesters.add(key);
        semesters.push({ name, dataSemester });
      });
    });

    const courses = [];
    const seenCourses = new Set();

    // The current JWXT timetable encodes weekdays in td class names instead of
    // repeating them in course text. Read those cells before the generic table fallback.
    documents.forEach((doc) => {
      [...doc.querySelectorAll("table.courseTable td.td-content")].forEach((cell) => {
        const dayToken = [...cell.classList].find((value) => /^[1-7]$/.test(value));
        const day = Number.parseInt(dayToken, 10);
        if (!dayLabels[day]) return;
        const containers = [...cell.querySelectorAll(":scope > .tdHtml")];
        (containers.length ? containers : [cell]).forEach((container) => {
          splitCourseBlocks(container).forEach((block) => {
            if (onlinePattern.test(block.content)) return;
            const codeMatch = block.content.match(/\b[A-Za-z][A-Za-z0-9]*\d[A-Za-z0-9]*\.\d+\b/);
            const code = codeMatch ? codeMatch[0] : undefined;
            const records = scheduleRecordsFromBlock(block, day);
            if (records.length) {
              records.forEach((record) => uniquePush(courses, seenCourses, {
                name: block.name,
                code,
                teacher: record.teacher,
                scheduleText: record.scheduleText,
                location: record.location,
                dataSemester: semesters.length ? semesters[0].dataSemester : ""
              }));
              return;
            }
            const locationText = locationFromBlock(block.content) || undefined;
            uniquePush(courses, seenCourses, {
              name: block.name,
              code,
              teacher: teacherFromBlock(block, code, locationText) || undefined,
              scheduleText: scheduleTextFromBlock(block.content, day),
              location: locationText,
              dataSemester: semesters.length ? semesters[0].dataSemester : ""
            });
          });
        });
      });
    });

    if (courses.length) return { semesters, courses };

    documents.forEach((doc) => {
      const rows = [...doc.querySelectorAll("tr")];
      let currentDataSemester = semesters.length ? semesters[0].dataSemester : "";
      rows.forEach((tr) => {
        const rowText = text(tr.innerText);
        if (!rowText) return;

        const attrSemester = text(tr.getAttribute("data-semester") || (tr.dataset ? tr.dataset.semester : ""));
        if (attrSemester) currentDataSemester = attrSemester;

        let name = "";
        const named = tr.querySelector(".showSchedules, .course-name, h3, h4, strong, a[title]");
        if (named) name = text(named.textContent || named.getAttribute("title"));
        if (!name) {
          const cellTexts = [...tr.querySelectorAll("td, th")].map((cell) => text(cell.innerText)).filter(Boolean);
          name = cellTexts.find((value) =>
            value.length >= 2 &&
            value.length <= 40 &&
            !looksLikeScheduleText(value) &&
            !/学分|教师|考试|考察|周[一二三四五六日天]|星期[一二三四五六日天]|第.{0,10}节|校区|教室|地点/.test(value)
          ) || "";
        }
        if (name.length < 2) return;

        const rowHtml = tr.innerHTML || "";
        const codeMatch = rowHtml.match(/\[([A-Za-z0-9]+)\]/);
        const creditsMatch = rowHtml.match(/学分\(([\d.]+)\)/);
        const teacherMatch = rowHtml.match(/(?:授课教师|教师)[：:]([^<]+)/);
        const assessmentMatch = rowHtml.match(/(考试|考察|PnP)/i);

        const cellTexts = [...tr.querySelectorAll("td")].map((cell) => text(cell.innerText)).filter(Boolean);
        let scheduleText = cellTexts.find(looksLikeScheduleText) || "";
        if (!scheduleText) {
          const longText = cellTexts.find((value) =>
            value.includes("节") && (value.includes("周") || value.includes("星期") || value.includes("周一"))
          );
          if (longText) scheduleText = longText;
        }
        let location = cellTexts.find(looksLikeLocation) || "";
        if (!location && scheduleText && looksLikeLocation(scheduleText)) {
          location = scheduleText;
        }

        if (!scheduleText || onlinePattern.test([name, rowText, scheduleText, location].join(" "))) return;

        uniquePush(courses, seenCourses, {
          name,
          code: codeMatch ? codeMatch[1] : undefined,
          credits: creditsMatch ? toMaybeNumber(creditsMatch[1]) : undefined,
          teacher: teacherMatch ? text(teacherMatch[1]) : undefined,
          assessmentMethod: assessmentMatch ? assessmentMatch[1] : undefined,
          scheduleText,
          location: location || undefined,
          dataSemester: currentDataSemester || (semesters.length ? semesters[0].dataSemester : "")
        });
      });
    });

    if (!courses.length) {
      documents.forEach((doc) => {
        const html = doc.body ? doc.body.innerHTML : "";
        if (!html) return;
        const semestersFromHtml = [...html.matchAll(/<option[^>]*value=["']([^"']+)["'][^>]*>([^<]+)<\/option>/g)];
        semestersFromHtml.forEach((match) => {
          const dataSemester = text(match[1]);
          const name = text(match[2]);
          if (!name) return;
          if (!semesterValuePattern.test(dataSemester) && !/(学期|春|秋|夏|冬|\d{4}-\d{4})/.test(name)) return;
          const key = dataSemester + "|" + name;
          if (seenSemesters.has(key)) return;
          seenSemesters.add(key);
          semesters.push({ name, dataSemester });
        });

        const rowMatches = [...html.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)];
        rowMatches.forEach((match) => {
          const trHtml = match[1];
          const flat = text(trHtml.replace(/<[^>]+>/g, " "));
          if (!looksLikeScheduleText(flat)) return;
          const nameMatch = trHtml.match(/class=["'][^"']*(?:showSchedules|course-name)[^"']*["'][^>]*>([^<]+)/) ||
            trHtml.match(/<h3[^>]*>([^<]+)<\/h3>/);
          const name = nameMatch ? text(nameMatch[1]) : "";
          if (name.length < 2) return;
          const codeMatch = trHtml.match(/\[([A-Za-z0-9]+)\]/);
          const creditsMatch = trHtml.match(/学分\(([\d.]+)\)/);
          const teacherMatch = trHtml.match(/(?:授课教师|教师)[：:]([^<]+)/);
          const assessmentMatch = trHtml.match(/(考试|考察|PnP)/i);
          const tdTexts = [...trHtml.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/g)]
            .map((item) => text(item[1].replace(/<[^>]+>/g, " ")))
            .filter(Boolean);
          const scheduleText = tdTexts.find(looksLikeScheduleText) || flat;
          if (!looksLikeScheduleText(scheduleText) || onlinePattern.test(scheduleText)) return;
          const location = tdTexts.find(looksLikeLocation) || undefined;
          uniquePush(courses, seenCourses, {
            name,
            code: codeMatch ? codeMatch[1] : undefined,
            credits: creditsMatch ? toMaybeNumber(creditsMatch[1]) : undefined,
            teacher: teacherMatch ? text(teacherMatch[1]) : undefined,
            assessmentMethod: assessmentMatch ? assessmentMatch[1] : undefined,
            scheduleText,
            location,
            dataSemester: semesters.length ? semesters[0].dataSemester : ""
          });
        });
      });
    }

    if (!semesters.length) {
      const firstCourseSemester = courses.find((course) => course.dataSemester && semesterValuePattern.test(course.dataSemester));
      semesters.push({
        name: firstCourseSemester ? firstCourseSemester.dataSemester : "当前学期",
        dataSemester: firstCourseSemester ? firstCourseSemester.dataSemester : "current"
      });
    }

    return { semesters, courses };
  };

  const schedulePayload = extractSchedulePayload();
  if (mode === "schedule" && schedulePayload.courses.length) {
    return JSON.stringify({ phase: "schedule_data", payload: schedulePayload });
  }

  return JSON.stringify({
    phase: "waiting",
    body: body.slice(0, 1000),
    rows: []
  });
})("__MODE__");
