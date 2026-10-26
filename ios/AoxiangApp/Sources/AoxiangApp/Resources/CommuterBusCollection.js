const injectedBusNo = __BUS_NO__;
const fetchTimeoutMs = 12000;

const fetchResponse = async (url, options) => {
  const controller = typeof AbortController === "function" ? new AbortController() : null;
  const timer = controller ? setTimeout(() => controller.abort(), fetchTimeoutMs) : null;
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

const busPost = async (path, fields) => {
  const body = Object.keys(fields)
    .map(key => encodeURIComponent(key) + "=" + encodeURIComponent(String(fields[key] == null ? "" : fields[key])))
    .join("&") + "&";
  const response = await fetchResponse(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Accept: "application/json, text/plain, */*"
    },
    body
  });
  if (!response.ok) throw new Error("HTTP " + response.status + " " + path);
  return response.json();
};

const busDateParts = date => {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "numeric",
    day: "numeric"
  }).formatToParts(date);
  const get = type => Number(parts.find(part => part.type === type).value);
  return { year: get("year"), month: get("month"), day: get("day") };
};

const busDate = date => {
  const value = busDateParts(date);
  return value.year + "/" + value.month + "/" + value.day;
};

const busIsoDate = date => {
  const value = busDateParts(date);
  return value.year + "-" + String(value.month).padStart(2, "0") + "-" + String(value.day).padStart(2, "0");
};

const responseItems = response => response && response.data;
const busFailed = response => !response || response.isSuccess === false ||
  String(response.isSuccess).toLowerCase() === "false";

const responseError = response => {
  if (!response) return "校车接口无响应";
  const data = response.data || {};
  const values = [
    response.message, response.msg, response.Message, response.Msg,
    response.error, response.errorMessage, response.ErrorMessage,
    response.tip, response.title, data.message, data.msg, data.Message, data.Msg
  ];
  for (const value of values) {
    const text = String(value == null ? "" : value).replace(/\s+/g, " ").trim();
    if (text && text !== "null" && text !== "undefined") return text;
  }
  return "校车接口返回失败";
};

const isUnknownUser = message => /用户不存在|工号不存在|未找到用户|未找到该用户|账号不存在/.test(String(message || ""));

const collectBus = async () => {
  let no = String(injectedBusNo == null ? "" : injectedBusNo).trim();
  let storedNo = "";
  try { storedNo = String(localStorage.getItem("NO") || "").trim(); } catch (_) {}
  if (!no && storedNo) no = storedNo;
  if (!no) {
    return { phase: "target_error", target: "bus", message: "校车身份参数缺失，请先登录教务系统" };
  }

  let iconResponse = null;
  let identityError = "";
  try {
    iconResponse = await busPost("/api/GetIcon", { GH: no, no });
    const error = busFailed(iconResponse) ? responseError(iconResponse) : "";
    if (isUnknownUser(error)) identityError = error;
  } catch (_) {}

  if (identityError && injectedBusNo && String(injectedBusNo).trim() !== no) {
    no = String(injectedBusNo).trim();
    try { localStorage.removeItem("NO"); } catch (_) {}
    identityError = "";
    try {
      iconResponse = await busPost("/api/GetIcon", { GH: no, no });
      const error = busFailed(iconResponse) ? responseError(iconResponse) : "";
      identityError = isUnknownUser(error) ? error : "";
    } catch (_) {}
  }

  const today = new Date();
  const tomorrow = new Date(today.getTime() + 24 * 60 * 60 * 1000);
  const reservations = [];
  const seenReservations = new Set();
  let reservationError = identityError;
  let reservationRequests = 0;
  for (const status of ["待核验", ""]) {
    let response;
    try {
      response = await busPost("/api/GetMyAppointment", { YYRGH: no, YYZT: status, no });
    } catch (error) {
      if (!reservationError) reservationError = String(error && error.message || error || "").trim();
      continue;
    }
    const data = responseItems(response);
    if (busFailed(response) || !data || !Array.isArray(data.list)) {
      if (!reservationError) reservationError = responseError(response);
      continue;
    }
    reservationRequests += 1;
    data.list.forEach(item => {
      const key = JSON.stringify(item);
      if (seenReservations.has(key)) return;
      seenReservations.add(key);
      reservations.push(item);
    });
  }

  let routesResponse = null;
  try {
    routesResponse = await busPost("/api/GetRouteByType", { type: "通勤车", no });
  } catch (error) {
    if (!reservationError && reservationRequests === 0) {
      reservationError = String(error && error.message || error || "").trim();
    }
  }
  if (!reservationError && reservationRequests === 0 && busFailed(routesResponse)) {
    reservationError = responseError(routesResponse);
  }

  const routeData = routesResponse && routesResponse.data;
  const routesComplete = !!(!busFailed(routesResponse) && routeData && Array.isArray(routeData.filteredBusRoutes));
  const routes = routesComplete ? routeData.filteredBusRoutes : [];
  const tripGroups = [];
  let tripRequests = 0;
  let tripResponses = 0;
  for (const route of routes) {
    for (const day of [today, tomorrow]) {
      tripRequests += 1;
      let response;
      try {
        response = await busPost("/api/GetReserveInfoList", {
          rq: busDate(day),
          xllx: "通勤车",
          xlId: route.Objid,
          gh: no,
          no
        });
      } catch (_) {
        continue;
      }
      if (busFailed(response) || !Array.isArray(response.data)) continue;
      tripResponses += 1;
      if (!response.data.length) continue;
      tripGroups.push({
        date: busIsoDate(day),
        routeId: route.Objid || "",
        routeName: route.Name || "",
        items: response.data
      });
    }
  }

  return {
    phase: "bus_api_raw",
    no,
    icon: iconResponse,
    routes: routesResponse,
    reservations: {
      isSuccess: reservationRequests === 2,
      data: { list: reservations },
      message: reservationError
    },
    tripGroups,
    routesComplete,
    reservationsComplete: reservationRequests === 2,
    tripsComplete: routesComplete && tripResponses === tripRequests,
    reservationError
  };
};

return JSON.stringify(await collectBus());
