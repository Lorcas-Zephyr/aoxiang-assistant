import webview from '@ohos.web.webview';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import picker from '@ohos.file.picker';
import fs from '@ohos.file.fs';
import { CredentialStore } from '../model/CredentialStore';
import { Grade, GradeMath } from '../model/GradeModel';
import { Course, CoursePresetColors, Semester, TimeSlot } from '../model/CourseModel';
import { WeekUtils } from '../model/WeekUtils';
import { IcsExport } from '../model/IcsExport';
// import { AppLogger } from '../model/AppLogger';
import { ScheduleGrid } from '../components/ScheduleGrid';
import { Constants, LoginPhase, LoginTarget } from '../common/Constants';
import { BusinessError } from '@kit.BasicServicesKit';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;
  @State username: string = '';
  @State password: string = '';
  @State smsCode: string = '';
  @State loginPhase: string = '';
  @State statusText: string = '';
  @State hasCredentials: boolean = false;
  @State savedAccount: string = '';
  @State showLoginForm: boolean = false;
  @State showSmsForm: boolean = false;
  @State showWebView: boolean = false;
  @State currentTarget: string = LoginTarget.SCHEDULE;
  @State webProgress: number = 0;
  @State grades: Grade[] = [];
  @State webViewSrc: string = '';
  @State electricityBalance: number = -1;
  @State apiGpa: number = -1;
  @State courses: Course[] = [];
  @State semesters: Semester[] = [];
  @State selectedSemesterIndex: number = 0;
  @State selectedWeekOffset: number = 0;
  @State showSemesterDialog: boolean = false;
  @State editingSemester: Semester | undefined = undefined;
  @State semNameInput: string = '';
  @State semStartDateInput: string = '';
  @State semWeekCountInput: string = '';
  @State showCourseDialog: boolean = false;
  @State editingCourse: Course | undefined = undefined;
  @State courseNameInput: string = '';
  @State courseCodeInput: string = '';
  @State courseTeacherInput: string = '';
  @State courseLocationInput: string = '';
  @State courseSlotsInput: string = '';
  @State courseColorIndex: number = 0;
  @State pendingSemDate: Date = new Date();
  @State showCourseDetail: boolean = false;
  @State detailCourse: Course | undefined = undefined;
  @State showConfirmDialog: boolean = false;
  @State confirmTitle: string = '';
  @State confirmMessage: string = '';
  @State interactiveMode: boolean = false;
  @State showCourseColorDialog: boolean = false;
  @State colorPickCourse: Course | undefined = undefined;
  @StorageProp('topRectHeight') topRectHeight: number = 0;

  private webController: webview.WebviewController = new webview.WebviewController();
  private tabsController: TabsController = new TabsController();
  private credentialStore: CredentialStore = new CredentialStore();
  private autoCollectScript: string = '';
  private apiCollectScript: string = '';
  private pollTimer: number = -1;
  private attempts: number = 0;
  private credentialsSubmitted: boolean = false;
  private smsSubmitted: boolean = false;
  private pendingSmsCode: string = '';
  private navigationCooldownUntil: number = 0;
  private gradeReadyAt: number = 0;
  private electricityReadyAt: number = 0;
  private smsSubmittedAt: number = 0;
  private gradePref: preferences.Preferences | undefined = undefined;

  async aboutToAppear(): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext;
    await this.credentialStore.init(context);
    this.gradePref = await preferences.getPreferences(context, 'campus_private');
    await this.loadScript(context);
    await this.refreshCredentialState();
    this.loadGradesFromPref();
    this.loadElectricityFromPref();
    this.loadCoursesFromPref();
    console.info(`aboutToAppear done: grades=${this.grades.length} electricity=${this.electricityBalance} hasCreds=${this.hasCredentials}`);
  }

  aboutToDisappear(): void {
    this.stopPolling();
  }

  private async loadScript(context: common.UIAbilityContext): Promise<void> {
    try {
      const rawBuf: Uint8Array = await context.resourceManager.getRawFileContent('auto_collect.js');
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      this.autoCollectScript = decoder.decodeToString(rawBuf);
    } catch (e) {
      console.error('load auto_collect.js failed');
    }
    try {
      const rawBuf: Uint8Array = await context.resourceManager.getRawFileContent('api_collect.js');
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      this.apiCollectScript = decoder.decodeToString(rawBuf);
    } catch (e) {
      console.error('load api_collect.js failed');
    }
  }

  private async refreshCredentialState(): Promise<void> {
    if (!this.credentialStore.hasCredentials()) {
      this.hasCredentials = false;
      this.savedAccount = '';
      return;
    }
    const creds: string[] = await this.credentialStore.readCredentials();
    if (creds[0].length === 0) {
      await this.credentialStore.clearCredentials();
      this.hasCredentials = false;
      this.savedAccount = '';
      return;
    }
    this.hasCredentials = true;
    this.savedAccount = creds[0];
    this.username = creds[0];
    this.password = creds[1];
  }

  private maskAccount(account: string): string {
    if (account.length <= 4) {
      return account;
    }
    return account.slice(0, 2) + '****' + account.slice(account.length - 2);
  }

  private loadGradesFromPref(): void {
    if (this.gradePref === undefined) {
      return;
    }
    try {
      const raw: string = this.gradePref.getSync('grades', '') as string;
      if (raw.length === 0) {
        return;
      }
      const arr: Object[] = JSON.parse(raw) as Object[];
      const out: Grade[] = [];
      for (let i = 0; i < arr.length; i++) {
        const obj: Record<string, Object> = arr[i] as Record<string, Object>;
        out.push(Grade.fromJsonObject(obj));
      }
      this.grades = out;
    } catch (e) {
      console.error('loadGrades failed');
    }
  }

  private saveGradesToPref(): void {
    if (this.gradePref === undefined) {
      return;
    }
    try {
      const arr: Object[] = [];
      for (let i = 0; i < this.grades.length; i++) {
        arr.push(this.grades[i].toJsonObject() as Object);
      }
      this.gradePref.putSync('grades', JSON.stringify(arr));
      this.gradePref.flushSync();
    } catch (e) {
      console.error('saveGrades failed');
    }
  }

  private loadElectricityFromPref(): void {
    if (this.gradePref === undefined) {
      return;
    }
    try {
      const raw: string = this.gradePref.getSync('electricity_balance', '') as string;
      if (raw.length > 0) {
        const val: number = parseFloat(raw);
        if (isFinite(val) && val >= 0) {
          this.electricityBalance = val;
        }
      }
    } catch (e) {
      console.error('loadElectricity failed');
    }
  }

  private saveElectricityToPref(): void {
    if (this.gradePref === undefined) {
      return;
    }
    try {
      this.gradePref.putSync('electricity_balance', this.electricityBalance < 0 ? '' : this.electricityBalance.toString());
      this.gradePref.flushSync();
    } catch (e) {
      console.error('saveElectricity failed');
    }
  }

  private assignCourseColors(): void {
    for (let i = 0; i < this.courses.length; i++) {
      this.courses[i].colorIndex = i % CoursePresetColors.COLORS.length;
    }
  }

  private loadCoursesFromPref(): void {
    if (this.gradePref === undefined) {
      return;
    }
    try {
      const raw: string = this.gradePref.getSync('courses', '') as string;
      if (raw.length === 0) {
        return;
      }
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const semArr: Object[] = parsed['semesters'] as Object[];
      const couArr: Object[] = parsed['courses'] as Object[];
      const semOut: Semester[] = [];
      for (let i = 0; i < semArr.length; i++) {
        semOut.push(Semester.fromJsObject(semArr[i] as Record<string, Object>));
      }
      const couOut: Course[] = [];
      for (let i = 0; i < couArr.length; i++) {
        couOut.push(Course.fromRecord(couArr[i] as Record<string, Object>));
      }
      this.semesters = semOut;
      this.courses = couOut;
      if (this.selectedSemesterIndex >= this.semesters.length) {
        this.selectedSemesterIndex = 0;
      }
      this.tryJumpToFirstCourseWeek();
    } catch (e) {
      console.error('loadCourses failed');
    }
  }

  private saveCoursesToPref(): void {
    if (this.gradePref === undefined) {
      return;
    }
    try {
      const semArr: Object[] = [];
      for (let i = 0; i < this.semesters.length; i++) {
        semArr.push(this.semesters[i].toRecord() as Object);
      }
      const couArr: Object[] = [];
      for (let i = 0; i < this.courses.length; i++) {
        couArr.push(this.courses[i].toRecord() as Object);
      }
      const data: Record<string, Object> = { 'semesters': semArr, 'courses': couArr };
      this.gradePref.putSync('courses', JSON.stringify(data));
      this.gradePref.flushSync();
    } catch (e) {
      console.error('saveCourses failed');
    }
  }

  private electricityBalanceText(): string {
    return this.electricityBalance < 0 ? '--' : this.electricityBalance.toFixed(2);
  }

  private currentSemesterCourses(): Course[] {
    if (this.semesters.length === 0) {
      return this.courses;
    }
    const sem: Semester = this.semesters[this.selectedSemesterIndex];
    const out: Course[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      if (this.courses[i].dataSemester === sem.dataSemester) {
        out.push(this.courses[i]);
      }
    }
    const dayOrder: number[] = [1, 2, 3, 4, 5, 6, 7, 0];
    out.sort((a: Course, b: Course) => {
      const aSlot: TimeSlot | undefined = a.timeSlots.length > 0 ? a.timeSlots[0] : undefined;
      const bSlot: TimeSlot | undefined = b.timeSlots.length > 0 ? b.timeSlots[0] : undefined;
      const dayA: number = aSlot !== undefined ? dayOrder.indexOf(aSlot.dayOfWeek) : 7;
      const dayB: number = bSlot !== undefined ? dayOrder.indexOf(bSlot.dayOfWeek) : 7;
      if (dayA !== dayB) {
        return dayA - dayB;
      }
      const secA: number = aSlot !== undefined ? aSlot.sectionStart : 99;
      const secB: number = bSlot !== undefined ? bSlot.sectionStart : 99;
      return secA - secB;
    });
    return out;
  }

  private selectedSemester(): Semester | undefined {
    if (this.semesters.length === 0) {
      return undefined;
    }
    if (this.selectedSemesterIndex >= this.semesters.length) {
      this.selectedSemesterIndex = 0;
    }
    return this.semesters[this.selectedSemesterIndex];
  }

  private selectedWeek(): number {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined) {
      return 1;
    }
    const result: number = WeekUtils.currentWeek(sem.startDate, sem.weekCount, this.selectedWeekOffset);
    console.info(`selectedWeek: startDate=${sem.startDate} weekCount=${sem.weekCount} offset=${this.selectedWeekOffset} week=${result}`);
    return result;
  }

  private selectedWeekStartDate(): string {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined || sem.startDate.length === 0) {
      return '';
    }
    const result: string = WeekUtils.formatDate(WeekUtils.weekStart(sem.startDate, this.selectedWeek()));
    console.info(`selectedWeekStartDate: week=${this.selectedWeek()} weekStart=${result}`);
    return result;
  }

  private canMoveWeek(direction: number): boolean {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined || sem.startDate.length === 0) {
      return false;
    }
    const current: number = this.selectedWeek();
    const weekCount: number = Math.max(1, sem.weekCount);
    if (direction > 0) {
      return current < weekCount;
    }
    return current > 1;
  }

  private moveWeek(direction: number): void {
    if (!this.canMoveWeek(direction)) {
      return;
    }
    this.selectedWeekOffset += direction;
    console.info(`moveWeek: direction=${direction} offset=${this.selectedWeekOffset} week=${this.selectedWeek()}`);
  }

  private resetWeek(): void {
    this.selectedWeekOffset = 0;
  }

  private autoFirstCourseWeek(): number {
    const courses: Course[] = this.currentSemesterCourses();
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined || courses.length === 0) {
      return 0;
    }
    const maxWeek: number = Math.max(1, sem.weekCount);
    for (let w = 1; w <= maxWeek; w++) {
      for (let i = 0; i < courses.length; i++) {
        for (let j = 0; j < courses[i].timeSlots.length; j++) {
          const slot: TimeSlot = courses[i].timeSlots[j];
          if (WeekUtils.isWeekInRange(w, slot.weekRange) &&
            WeekUtils.matchesRepeatRule(w, slot.repeatRule)) {
            return w;
          }
        }
      }
    }
    return 0;
  }

  private tryJumpToFirstCourseWeek(): void {
    if (this.selectedWeekOffset !== 0) {
      return;
    }
    const firstWeek: number = this.autoFirstCourseWeek();
    if (firstWeek <= 0) {
      return;
    }
    const current: number = this.selectedWeek();
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined || sem.startDate.length === 0) {
      return;
    }
    const inRange: boolean = this.currentSemesterCourses().some((c: Course) =>
      c.timeSlots.some((s: TimeSlot) =>
        s.dayOfWeek >= 1 && s.dayOfWeek <= 7 &&
        s.sectionStart >= 1 && s.sectionEnd >= s.sectionStart &&
        WeekUtils.isWeekInRange(current, s.weekRange) &&
        WeekUtils.matchesRepeatRule(current, s.repeatRule)
      )
    );
    if (!inRange) {
      this.selectedWeekOffset = firstWeek - current;
      console.info(`tryJumpToFirstCourseWeek: jump to week=${firstWeek} offset=${this.selectedWeekOffset}`);
    }
  }

  private openStartDatePicker(): void {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined) {
      return;
    }
    let initial: Date = new Date();
    if (sem.startDate.length > 0) {
      initial = WeekUtils.parseStartDate(sem.startDate);
    }
    this.getUIContext().showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(2030, 11, 31),
      selected: initial,
      showTime: false,
      onDateAccept: (value: Date) => {
        this.confirmStartDate(value);
      },
    });
  }

  private confirmStartDate(date: Date): void {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined) {
      return;
    }
    sem.startDate = WeekUtils.formatDate(WeekUtils.mondayOnOrBefore(date));
    this.selectedWeekOffset = 0;
    const refreshed: Semester[] = [];
    for (let i = 0; i < this.semesters.length; i++) {
      refreshed.push(this.semesters[i]);
    }
    this.semesters = refreshed;
    this.saveCoursesToPref();
    console.info(`confirmStartDate: startDate=${sem.startDate} week=${this.selectedWeek()} weekStart=${this.selectedWeekStartDate()}`);
  }

  private weightedPoint(): string {
    if (this.apiGpa >= 0 && this.apiGpa <= 5) {
      return this.apiGpa.toFixed(3);
    }
    if (this.grades.length === 0) {
      return '--';
    }
    const credits: number[] = [];
    const points: number[] = [];
    for (let i = 0; i < this.grades.length; i++) {
      credits.push(this.grades[i].credits);
      points.push(this.grades[i].point);
    }
    const result: number = GradeMath.weightedAverage(credits, points);
    return isNaN(result) ? '--' : result.toFixed(3);
  }

  private weightedScore(): string {
    if (this.grades.length === 0) {
      return '--';
    }
    const credits: number[] = [];
    const scores: number[] = [];
    for (let i = 0; i < this.grades.length; i++) {
      credits.push(this.grades[i].credits);
      scores.push(this.grades[i].score);
    }
    const result: number = GradeMath.weightedAverage(credits, scores);
    return isNaN(result) ? '--' : result.toFixed(2);
  }

  private enterInteractiveMode(): void {
    this.interactiveMode = true;
    this.statusText = '请完成安全验证后点击继续';
  }

  private exitInteractiveMode(): void {
    this.interactiveMode = false;
  }

  private async onSaveCredentials(): Promise<void> {
    if (this.username.length === 0 || this.password.length === 0) {
      this.statusText = '请输入账号和密码';
      return;
    }
    const ok: boolean = await this.credentialStore.saveCredentials(this.username, this.password);
    if (!ok) {
      this.statusText = '无法安全保存账号，请重试';
      return;
    }
    this.showLoginForm = false;
    this.hasCredentials = true;
    this.savedAccount = this.username;
    this.statusText = '账号已保存';
    await this.startPortal(this.currentTarget, false);
  }

  private async onSmsSubmit(): Promise<void> {
    if (this.smsCode.length < 4) {
      this.statusText = '请输入有效验证码';
      return;
    }
    this.pendingSmsCode = this.smsCode;
    this.smsSubmitted = false;
    this.smsSubmittedAt = Date.now();
    this.showSmsForm = false;
  }

  private async startPortal(target: string, automatic: boolean): Promise<void> {
    this.stopPolling();
    this.currentTarget = target;
    this.showLoginForm = false;
    this.showSmsForm = false;
    this.attempts = 0;
    this.credentialsSubmitted = false;
    this.smsSubmitted = false;
    this.pendingSmsCode = '';
    this.gradeReadyAt = 0;
    this.electricityReadyAt = 0;
    this.navigationCooldownUntil = 0;
    this.smsSubmittedAt = 0;
    this.loginPhase = '';
    this.statusText = '正在连接教务系统…';
    this.webProgress = 0;

    const ssoUrl: string = target === LoginTarget.ELECTRICITY ? Constants.ELECTRICITY_SSO : Constants.EDUCATION_SSO;
    this.webViewSrc = ssoUrl;
    this.showWebView = true;
    setTimeout(() => {
      this.startPolling();
    }, 1500);
  }

  private async onSignOut(): Promise<void> {
    await this.credentialStore.clearCredentials();
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (e) {
      console.error('clearCookies failed');
    }
    this.hasCredentials = false;
    this.savedAccount = '';
    this.username = '';
    this.password = '';
    this.showWebView = false;
    this.grades = [];
    this.electricityBalance = -1;
    this.courses = [];
    this.semesters = [];
    this.selectedSemesterIndex = 0;
    this.selectedWeekOffset = 0;
    this.statusText = '已退出登录';
  }

  private async persistLoginState(): Promise<void> {
    await this.credentialStore.markCredentialsVerified();
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (e) {
      console.error('saveCookieSync failed');
    }
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      this.pollOnce();
    }, 1000) as number;
  }

  private stopPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private pollOnce(): void {
    if (!this.showWebView || this.attempts >= 180) {
      this.stopPolling();
      this.statusText = this.attempts >= 180 ? '自动采集超时，请稍后重试' : this.statusText;
      return;
    }
    this.attempts++;
    if (this.webProgress < 60) {
      return;
    }

    const isCollectTarget: boolean = this.currentTarget === LoginTarget.GRADES ||
      this.currentTarget === LoginTarget.SCHEDULE || this.currentTarget === LoginTarget.ELECTRICITY;
    if (this.interactiveMode) {
      this.runLegacyScript();
      return;
    }
    if (isCollectTarget && this.apiCollectScript.length > 0) {
      try {
        const apiScript: string = this.buildApiScript();
        this.webController.runJavaScript(apiScript, (error: BusinessError, apiResult: string) => {
          if (error) {
            console.error(`api runJavaScript error: ${error.code} ${error.message}`);
            this.runLegacyScript();
            return;
          }
          const phase: string = this.extractPhase(apiResult);
          console.info(`api phase='${phase}' target=${this.currentTarget}`);
          if (phase === LoginPhase.API_UNAVAILABLE || phase === LoginPhase.TARGET_ERROR) {
            this.runLegacyScript();
            return;
          }
          this.handleJsResult(apiResult);
        });
      } catch (e) {
        console.error(`api runJavaScript exception: ${e}`);
        this.runLegacyScript();
      }
      return;
    }
    this.runLegacyScript();
  }

  private extractPhase(result: string): string {
    try {
      let parsed: Object = JSON.parse(result) as Object;
      if (typeof parsed === 'string') {
        parsed = JSON.parse(parsed as string) as Object;
      }
      const obj: Record<string, Object> = parsed as Record<string, Object>;
      const phaseVal: Object | undefined = obj['phase'];
      return phaseVal !== undefined && phaseVal !== null ? String(phaseVal) : '';
    } catch (e) {
      return '';
    }
  }

  private runLegacyScript(): void {
    const script: string = this.buildScript();
    try {
      this.webController.runJavaScript(script, (error: BusinessError, result: string) => {
        if (error) {
          console.error(`runJavaScript error: ${error.code} ${error.message}`);
          return;
        }
        console.info(`handleJsResult: ${result.substring(0, 120)}`);
        this.handleJsResult(result);
      });
    } catch (e) {
      console.error(`runJavaScript exception: ${e}`);
    }
  }

  private buildApiScript(): string {
    const now: number = Date.now();
    const allowNav: boolean = now >= this.navigationCooldownUntil;
    return this.apiCollectScript
      .replace('"__MODE__"', `"${this.currentTarget}"`)
      .replace('__ALLOW_NAV__', allowNav.toString());
  }

  private buildScript(): string {
    const now: number = Date.now();
    const allowNav: boolean = now >= this.navigationCooldownUntil;
    const canAutofill: boolean = !this.credentialsSubmitted && this.username.length > 0 && this.password.length > 0;
    const canFillSms: boolean = !this.smsSubmitted && this.pendingSmsCode.length > 0;

    return this.autoCollectScript
      .replace('"__MODE__"', `"${this.currentTarget}"`)
      .replace('__ALLOW_NAV__', allowNav.toString())
      .replace('__USERNAME__', JSON.stringify(this.username))
      .replace('__PASSWORD__', JSON.stringify(this.password))
      .replace('__SMS_CODE__', JSON.stringify(this.pendingSmsCode))
      .replace('__CAN_AUTOFILL__', canAutofill.toString())
      .replace('__CAN_FILL_SMS__', canFillSms.toString())
      .replace('__AUTH_EXITED__', 'false')
      .replace('__HEADLESS__', 'false');
  }

  private handleJsResult(result: string): void {
    try {
      let parsed: Object = JSON.parse(result) as Object;
      if (typeof parsed === 'string') {
        parsed = JSON.parse(parsed as string) as Object;
      }
      const obj: Record<string, Object> = parsed as Record<string, Object>;
      const phaseVal: Object | undefined = obj['phase'];
      const phase: string = phaseVal !== undefined && phaseVal !== null ? String(phaseVal) : '';
      this.loginPhase = phase;
      console.info(`handleJsResult phase='${phase}' target=${this.currentTarget} gradeReadyAt=${this.gradeReadyAt}`);

      if (phase === LoginPhase.CREDENTIALS_REQUIRED) {
        this.credentialsSubmitted = false;
        this.statusText = '需要教务账号';
        this.showLoginForm = true;
        return;
      }
      if (phase === LoginPhase.CREDENTIALS_ERROR) {
        this.credentialsSubmitted = false;
        this.statusText = '账号或密码有误';
        this.showLoginForm = true;
        return;
      }
      if (phase === LoginPhase.CREDENTIALS_SUBMITTING) {
        this.credentialsSubmitted = true;
        this.statusText = '正在验证账号…';
        return;
      }
      if (phase === LoginPhase.SMS_REQUIRED) {
        const smsErrorVal: Object | undefined = obj['smsError'];
        const smsError: boolean = smsErrorVal !== undefined && smsErrorVal !== null && smsErrorVal === true;
        if (!smsError && this.smsSubmittedAt > 0 && (Date.now() - this.smsSubmittedAt) < 5000) {
          console.info('sms_required right after submit, waiting for navigation…');
          return;
        }
        this.smsSubmitted = false;
        this.pendingSmsCode = '';
        this.statusText = smsError ? '短信验证码错误，请重新输入' : '需要短信验证码';
        this.showSmsForm = true;
        return;
      }
      if (phase === LoginPhase.SMS_SUBMITTING) {
        this.smsSubmitted = true;
        this.statusText = '正在验证短信验证码…';
        return;
      }
      if (phase === LoginPhase.CLICKED) {
        this.navigationCooldownUntil = Date.now() + 2500;
        this.statusText = '正在打开页面…';
        return;
      }
      if (phase === LoginPhase.PAGE) {
        this.navigationCooldownUntil = Date.now() + 1500;
        this.statusText = '页面加载中，请稍候…';
        return;
      }
      if (phase === LoginPhase.DATA && this.currentTarget === LoginTarget.GRADES) {
        if (this.gradeReadyAt === 0) {
          this.gradeReadyAt = Date.now() + 5000;
          console.info('gradeReadyAt set, countdown starts');
        }
        const seconds: number = Math.max(0, Math.floor((this.gradeReadyAt - Date.now() + 999) / 1000));
        if (seconds > 0) {
          this.statusText = `成绩加载中，还需 ${seconds} 秒…`;
        } else {
          console.info('countdown done, calling handleCollectedGrades');
          this.handleCollectedGrades(obj['rows'], undefined);
        }
        return;
      }
      if (phase === LoginPhase.SCHEDULE_DATA && this.currentTarget === LoginTarget.SCHEDULE) {
        this.handleCollectedSchedule(obj['payload']);
        return;
      }
      if (phase === LoginPhase.ELECTRICITY_DATA && this.currentTarget === LoginTarget.ELECTRICITY) {
        const balanceVal: Object | undefined = obj['balance'];
        console.info(`electricity_data balanceVal=${balanceVal} type=${typeof balanceVal}`);
        if (balanceVal !== undefined && balanceVal !== null) {
          const balance: number = parseFloat(String(balanceVal));
          console.info(`electricity_data balance=${balance} isFinite=${isFinite(balance)}`);
          if (isFinite(balance) && balance >= 0) {
            this.electricityBalance = balance;
            this.saveElectricityToPref();
            this.persistLoginState();
            this.stopPolling();
            this.showWebView = false;
            this.statusText = `电费余额: ${balance.toFixed(2)} 元`;
            this.currentTab = 0;
            this.tabsController.changeIndex(0);
            console.info(`electricity saved: balance=${this.electricityBalance} text=${this.electricityBalanceText()} showWebView=${this.showWebView} currentTab=${this.currentTab}`);
            return;
          }
        }
        this.statusText = '未能读取电费余额';
        return;
      }
      if (phase === LoginPhase.INTERACTIVE_LOGIN) {
        this.statusText = '需要手动完成安全验证';
        this.enterInteractiveMode();
        return;
      }
      if (phase === LoginPhase.CREDENTIALS_VALID) {
        this.exitInteractiveMode();
        this.statusText = '验证完成，继续采集…';
        return;
      }
      if (phase === LoginPhase.API_WAITING) {
        this.statusText = '正在读取数据…';
        return;
      }
      if (phase === LoginPhase.TARGET_ERROR) {
        const msgVal: Object | undefined = obj['message'];
        const msg: string = msgVal !== undefined && msgVal !== null ? String(msgVal) : '接口读取失败，请稍后重试';
        this.statusText = msg;
        return;
      }
      if (phase === LoginPhase.GRADE_API_RAW && this.currentTarget === LoginTarget.GRADES) {
        console.info('grade_api_raw received');
        this.handleCollectedGrades(obj['rows'], obj['gpa']);
        return;
      }
      if (phase === LoginPhase.SCHEDULE_API_RAW && this.currentTarget === LoginTarget.SCHEDULE) {
        console.info('schedule_api_raw received');
        this.handleCollectedSchedule(obj['payload']);
        return;
      }
      if (phase === LoginPhase.ELECTRICITY_API_RAW && this.currentTarget === LoginTarget.ELECTRICITY) {
        const balanceVal: Object | undefined = obj['balance'];
        if (balanceVal !== undefined && balanceVal !== null) {
          const balance: number = parseFloat(String(balanceVal));
          if (isFinite(balance) && balance >= 0) {
            this.electricityBalance = balance;
            this.saveElectricityToPref();
            this.persistLoginState();
            this.stopPolling();
            this.showWebView = false;
            this.statusText = `电费余额: ${balance.toFixed(2)} 元`;
            this.currentTab = 0;
            this.tabsController.changeIndex(0);
            console.info(`electricity_api saved: balance=${balance}`);
            return;
          }
        }
        this.statusText = '未能读取电费余额';
        return;
      }
      if (phase === LoginPhase.WAITING) {
        this.statusText = '正在查找目标页面…';
        return;
      }
    } catch (e) {
      console.error(`handleJsResult exception: ${e}`);
      this.statusText = '正在等待页面加载…';
    }
  }

  private handleCollectedGrades(rowsObj: Object | undefined, gpaVal: Object | undefined): void {
    console.info(`handleCollectedGrades called, rowsObj type=${typeof rowsObj}`);
    if (gpaVal !== undefined && gpaVal !== null) {
      const gpaNum: number = parseFloat(String(gpaVal));
      if (isFinite(gpaNum) && gpaNum >= 0 && gpaNum <= 5) {
        this.apiGpa = gpaNum;
      }
    }
    if (rowsObj === undefined || rowsObj === null) {
      console.info('handleCollectedGrades: rowsObj is null/undefined, stopping');
      this.stopPolling();
      this.showWebView = false;
      return;
    }
    const rawRows: Object[] = rowsObj as Object[];
    console.info(`handleCollectedGrades: rawRows.length=${rawRows.length}`);
    const out: Grade[] = [];
    for (let i = 0; i < rawRows.length; i++) {
      const cells: Object[] = rawRows[i] as Object[];
      if (cells.length < 4) {
        console.info(`handleCollectedGrades: row ${i} skipped, cells.length=${cells.length}`);
        continue;
      }
      const cellStrings: string[] = [];
      for (let j = 0; j < cells.length; j++) {
        cellStrings.push(cells[j] !== null && cells[j] !== undefined ? String(cells[j]) : '');
      }
      const g: Grade = Grade.fromTableRow(cellStrings);
      console.info(`handleCollectedGrades: row ${i} => ${g.course}`);
      out.push(g);
    }
    console.info(`handleCollectedGrades: out.length=${out.length}`);
    if (out.length === 0) {
      this.stopPolling();
      this.showWebView = false;
      return;
    }
    this.grades = out;
    this.saveGradesToPref();
    this.persistLoginState();
    this.stopPolling();
    this.showWebView = false;
    this.currentTab = 2;
    this.tabsController.changeIndex(2);
    console.info(`handleCollectedGrades: DONE, grades=${this.grades.length} GPA=${this.weightedPoint()} showWebView=${this.showWebView} currentTab=${this.currentTab}`);
  }

  private handleCollectedSchedule(payloadObj: Object | undefined): void {
    console.info(`handleCollectedSchedule called, payloadObj type=${typeof payloadObj}`);
    if (payloadObj === undefined || payloadObj === null) {
      console.info('handleCollectedSchedule: payloadObj is null/undefined');
      this.stopPolling();
      this.showWebView = false;
      this.statusText = '未能解析课表数据';
      return;
    }
    const payload: Record<string, Object> = payloadObj as Record<string, Object>;
    const semRaw: Object[] = payload['semesters'] as Object[];
    const couRaw: Object[] = payload['courses'] as Object[];
    console.info(`handleCollectedSchedule: semesters=${semRaw.length} courses=${couRaw.length}`);
    // AppLogger.info('ScheduleImport', `semesters=${semRaw.length} courses=${couRaw.length}`);
    const semOut: Semester[] = [];
    for (let i = 0; i < semRaw.length; i++) {
      semOut.push(Semester.fromJsObject(semRaw[i] as Record<string, Object>));
    }
    const couOut: Course[] = [];
    for (let i = 0; i < couRaw.length; i++) {
      const rawObj: Record<string, Object> = couRaw[i] as Record<string, Object>;
      console.info(`scheduleRawJson[${i}]: ${JSON.stringify(rawObj)}`);
      const parsed: Course = Course.fromRecord(rawObj);
      if (parsed.timeSlots.length === 0) {
        console.info(`scheduleRawJson[${i}]: skipped (no timeSlots after parse)`);
        continue;
      }
      couOut.push(parsed);
    }
    for (let i = 0; i < couOut.length; i++) {
      const cc: Course = couOut[i];
      const slotInfo: string[] = [];
      for (let j = 0; j < cc.timeSlots.length; j++) {
        const s: TimeSlot = cc.timeSlots[j];
        slotInfo.push(`[wr='${s.weekRange}' day=${s.dayOfWeek} sec=${s.sectionStart}-${s.sectionEnd}]`);
      }
      console.info(`scheduleRaw[${i}]: name='${cc.name}' scheduleText='${cc.scheduleText}' slots=${slotInfo.join(' ')}`);
    }
    if (couOut.length === 0 && semOut.length === 0) {
      this.stopPolling();
      this.showWebView = false;
      this.statusText = '没有解析到课表数据';
      return;
    }
    if (semOut.length === 0) {
      const s: Semester = new Semester();
      s.name = '当前学期';
      s.dataSemester = 'current';
      s.weekCount = Semester.computeWeekCount(couOut);
      semOut.push(s);
    } else {
      for (let i = 0; i < semOut.length; i++) {
        const semCourses: Course[] = [];
        for (let j = 0; j < couOut.length; j++) {
          if (couOut[j].dataSemester === semOut[i].dataSemester) {
            semCourses.push(couOut[j]);
          }
        }
        semOut[i].weekCount = Semester.computeWeekCount(semCourses);
      }
    }
    const defaultSemester: string = semOut.length > 0 ? semOut[0].dataSemester : 'current';
    const mergedSemCourses: Course[] = this.mergeCoursesBySemester(couOut, defaultSemester);
    const mergedAll: Course[] = this.mergeCoursesAcrossSemesters(couOut);
    // AppLogger.info('ScheduleImport', `afterMerge semCourses=${mergedSemCourses.length} allCourses=${mergedAll.length}`);
    this.semesters = semOut;
    this.courses = mergedAll;
    this.saveCoursesToPref();
    this.persistLoginState();
    this.selectedSemesterIndex = 0;
    this.selectedWeekOffset = 0;
    this.stopPolling();
    this.showWebView = false;
    if (mergedSemCourses.length === 0) {
      this.statusText = '该学期暂无课程';
    } else {
      this.statusText = `已导入 ${mergedSemCourses.length} 门课程`;
    }
    this.currentTab = 1;
    this.tabsController.changeIndex(1);
    this.tryJumpToFirstCourseWeek();
    console.info(`handleCollectedSchedule: DONE, courses=${this.courses.length} semesters=${this.semesters.length}`);
  }

  private mergeCoursesBySemester(courses: Course[], semester: string): Course[] {
    const inSem: Course[] = [];
    for (let i = 0; i < courses.length; i++) {
      if (courses[i].dataSemester === semester) {
        inSem.push(courses[i]);
      }
    }
    return Course.mergeByName(inSem);
  }

  private mergeCoursesAcrossSemesters(courses: Course[]): Course[] {
    const grouped: Record<string, Course[]> = {};
    const order: string[] = [];
    for (let i = 0; i < courses.length; i++) {
      const ds: string = courses[i].dataSemester;
      const existing: Course[] | undefined = grouped[ds];
      if (existing === undefined) {
        grouped[ds] = [courses[i]];
        order.push(ds);
      } else {
        existing.push(courses[i]);
      }
    }
    const out: Course[] = [];
    for (let i = 0; i < order.length; i++) {
      const merged: Course[] = Course.mergeByName(grouped[order[i]]);
      for (let j = 0; j < merged.length; j++) {
        out.push(merged[j]);
      }
    }
    return out;
  }

  build() {
    Stack() {
      Tabs({ barPosition: BarPosition.End, controller: this.tabsController }) {
        TabContent() {
          this.HomeContent()
        }
        .tabBar('')

        TabContent() {
          this.ScheduleContent()
        }
        .tabBar('')

        TabContent() {
          this.GradesContent()
        }
        .tabBar('')

        TabContent() {
          this.ManageContent()
        }
        .tabBar('')

        TabContent() {
          this.SettingsContent()
        }
        .tabBar('')
      }
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .scrollable(false)
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .barBackgroundColor(Color.Transparent)
      .barHeight(0)

      if (!this.showLoginForm && !this.showSmsForm && !this.showSemesterDialog && !this.showCourseDialog && !this.showConfirmDialog && !this.showCourseColorDialog && !this.showWebView && !this.interactiveMode) {
        this.FloatingTabBar()
      }

      if (this.showWebView) {
        this.WebViewOverlay()
      }

      if (this.showLoginForm) {
        this.LoginDialog()
      }

      if (this.showSmsForm) {
        this.SmsDialog()
      }

      if (this.showSemesterDialog) {
        this.SemesterDialogBuilder()
      }

      if (this.showCourseDialog) {
        this.CourseDialogBuilder()
      }

      if (this.showConfirmDialog) {
        this.ConfirmDialogBuilder()
      }

      if (this.showCourseColorDialog) {
        this.CourseColorDialog()
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  FloatingTabBar() {
    Row() {
      ForEach([
        { 'label': '首页', 'index': 0 },
        { 'label': '课表', 'index': 1 },
        { 'label': '成绩', 'index': 2 },
        { 'label': '管理', 'index': 3 },
        { 'label': '设置', 'index': 4 },
      ], (tab: Record<string, Object>) => {
        Column() {
          Text(tab['label'] as string)
            .fontSize(12)
            .fontColor(this.currentTab === (tab['index'] as number) ? $r('app.color.accent') : $r('app.color.text_hint'))
            .fontWeight(this.currentTab === (tab['index'] as number) ? FontWeight.Bold : FontWeight.Normal)
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          const idx: number = tab['index'] as number;
          this.currentTab = idx;
          this.tabsController.changeIndex(idx);
        })
      }, (tab: Record<string, Object>) => `tab_${tab['index']}`)
    }
    .width('92%')
    .height(56)
    .borderRadius(28)
    .backgroundColor($r('app.color.tab_bar_bg'))
    .shadow({ radius: 20, color: '#1A000000', offsetX: 0, offsetY: -2 })
    .position({ x: '4%', y: '100%' })
    .translate({ y: -80 })
    .zIndex(10)
  }

  @Builder
  HomeContent() {
    Scroll() {
      Column() {
        Text('翱翔助手')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: this.topRectHeight + 20, bottom: 8 })

        Text('西北工业大学教务助手')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ bottom: 32 })

        this.HomeMetrics()

        Row() {
          Button('导入课表')
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .fontSize(14)
            .borderRadius(8)
            .onClick(() => {
              if (!this.hasCredentials) {
                this.showLoginForm = true;
                this.currentTarget = LoginTarget.SCHEDULE;
                return;
              }
              this.startPortal(LoginTarget.SCHEDULE, false);
            })

          Button('更新成绩')
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .fontSize(14)
            .borderRadius(8)
            .margin({ left: 10 })
            .onClick(() => {
              if (!this.hasCredentials) {
                this.showLoginForm = true;
                this.currentTarget = LoginTarget.GRADES;
                return;
              }
              this.startPortal(LoginTarget.GRADES, false);
            })
        }
        .width('92%')
        .margin({ bottom: 10 })

        Button('查看电费')
          .width('92%')
          .height(44)
          .backgroundColor($r('app.color.button_secondary'))
          .fontColor(Color.White)
          .fontSize(14)
          .borderRadius(8)
          .onClick(() => {
            if (!this.hasCredentials) {
              this.showLoginForm = true;
              this.currentTarget = LoginTarget.ELECTRICITY;
              return;
            }
            this.startPortal(LoginTarget.ELECTRICITY, false);
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: 100 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    
  }

  @Builder
  HomeMetrics() {
    Column() {
      Row() {
        Column() {
          Text('GPA')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.weightedPoint())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4, bottom: 2 })
          Text('绩点')
            .fontSize(10)
            .fontColor($r('app.color.text_hint'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text('加权成绩')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.weightedScore())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4, bottom: 2 })
          Text('分')
            .fontSize(10)
            .fontColor($r('app.color.text_hint'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text('课程')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(`${this.grades.length}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4, bottom: 2 })
          Text('门')
            .fontSize(10)
            .fontColor($r('app.color.text_hint'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')

      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor($r('app.color.divider'))
        .margin({ top: 12, bottom: 12 })

      Row() {
        Column() {
          Text('电费余额')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.electricityBalanceText())
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4, bottom: 2 })
          Text('元')
            .fontSize(10)
            .fontColor($r('app.color.text_hint'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text('课表')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          Text(`${this.courses.length}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4, bottom: 2 })
          Text('门')
            .fontSize(10)
            .fontColor($r('app.color.text_hint'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
    }
    .width('92%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .padding(16)
    .margin({ bottom: 16 })
  }

  @Builder
  GradesMetrics() {
    Row() {
      Column() {
        Text('GPA')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text(this.weightedPoint())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4, bottom: 2 })
        Text('绩点')
          .fontSize(10)
          .fontColor($r('app.color.text_hint'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text('加权成绩')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text(this.weightedScore())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4, bottom: 2 })
        Text('分')
          .fontSize(10)
          .fontColor($r('app.color.text_hint'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Column() {
        Text('课程')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
        Text(`${this.grades.length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4, bottom: 2 })
        Text('门')
          .fontSize(10)
          .fontColor($r('app.color.text_hint'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('92%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .padding(16)
    .margin({ bottom: 16 })
  }

  @Builder
  ScheduleContent() {
    Column() {
      Row() {
        Text('课表')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))

        Blank()

        Button('导入')
          .height(32)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.accent'))
          .fontSize(13)
          .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
          .onClick(() => {
            if (!this.hasCredentials) {
              this.showLoginForm = true;
              this.currentTarget = LoginTarget.SCHEDULE;
              return;
            }
            this.startPortal(LoginTarget.SCHEDULE, false);
          })
      }
      .width('92%')
      .margin({ top: this.topRectHeight + 8, bottom: 12 })

      if (this.courses.length === 0) {
        Column() {
          Text(this.semesters.length === 0 ? '还没有课表数据' : '该学期暂无课程')
            .fontSize(14)
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 40 })
          if (this.semesters.length === 0) {
            Button('导入课表')
              .height(44)
              .backgroundColor($r('app.color.accent'))
              .fontColor(Color.White)
              .fontSize(14)
              .borderRadius(8)
              .margin({ top: 16 })
              .onClick(() => {
                if (!this.hasCredentials) {
                  this.showLoginForm = true;
                  this.currentTarget = LoginTarget.SCHEDULE;
                  return;
                }
                this.startPortal(LoginTarget.SCHEDULE, false);
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else {
        if (this.semesters.length > 1) {
          Row() {
            Button('‹')
              .fontSize(18)
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.accent'))
              .border({ width: 1, color: $r('app.color.border_light'), radius: 6 })
              .onClick(() => {
                if (this.selectedSemesterIndex > 0) {
                  this.selectedSemesterIndex--;
                  this.selectedWeekOffset = 0;
                }
              })
            Text(this.semesters[this.selectedSemesterIndex].name)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button('›')
              .fontSize(18)
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.accent'))
              .border({ width: 1, color: $r('app.color.border_light'), radius: 6 })
              .onClick(() => {
                if (this.selectedSemesterIndex < this.semesters.length - 1) {
                  this.selectedSemesterIndex++;
                  this.selectedWeekOffset = 0;
                }
              })
          }
          .width('92%')
          .margin({ bottom: 8 })
        }

        Row() {
          Button('‹')
            .fontSize(20)
            .width(40)
            .height(38)
            .backgroundColor(Color.Transparent)
            .fontColor(this.canMoveWeek(-1) ? $r('app.color.accent') : $r('app.color.text_hint'))
            .border({ width: 1, color: $r('app.color.border_light'), radius: 6 })
            .onClick(() => {
              this.moveWeek(-1);
            })

          Column() {
            Text(this.weekTitleText())
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .fontWeight(FontWeight.Bold)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row() {
              Text('本周')
                .fontSize(11)
                .fontColor(this.selectedWeekOffset === 0 ? $r('app.color.text_hint') : $r('app.color.accent'))
                .onClick(() => {
                  this.resetWeek();
                })
              Text('  |  设置第一周')
                .fontSize(11)
                .fontColor($r('app.color.text_hint'))
                .onClick(() => {
                  this.openStartDatePicker();
                })
            }
            .margin({ top: 2 })
            .justifyContent(FlexAlign.Center)
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          Button('›')
            .fontSize(20)
            .width(40)
            .height(38)
            .backgroundColor(Color.Transparent)
            .fontColor(this.canMoveWeek(1) ? $r('app.color.accent') : $r('app.color.text_hint'))
            .border({ width: 1, color: $r('app.color.border_light'), radius: 6 })
            .onClick(() => {
              this.moveWeek(1);
            })
        }
        .width('92%')
        .margin({ bottom: 8 })

        Column() {
          ScheduleGrid({
            courses: this.currentSemesterCourses(),
            week: this.selectedWeek(),
            weekStartDate: this.selectedWeekStartDate(),
          })
        }
        .width('92%')
        .backgroundColor($r('app.color.schedule_bg'))
        .borderRadius(12)
        .padding(8)
        .layoutWeight(1)
        .parallelGesture(
          PanGesture({ direction: PanDirection.Horizontal, distance: 80 })
            .onActionEnd((event: GestureEvent) => {
              const dx: number = event.offsetX;
              console.info(`schedule pan dx=${dx}`);
              if (dx < -80) {
                this.moveWeek(1);
              } else if (dx > 80) {
                this.moveWeek(-1);
              }
            })
        )
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
  }

  private weekTitleText(): string {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined) {
      return '课表';
    }
    if (sem.startDate.length === 0) {
      return `${sem.name} · 未设置第一周`;
    }
    return `${sem.name} · 第${this.selectedWeek()}周`;
  }

  @Builder
  GradesContent() {
    Scroll() {
      Column() {
        Row() {
          Text('成绩')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))

          Blank()

          Button('更新')
            .height(32)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.accent'))
            .fontSize(13)
            .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
            .onClick(() => {
              if (!this.hasCredentials) {
                this.showLoginForm = true;
                this.currentTarget = LoginTarget.GRADES;
                return;
              }
              this.startPortal(LoginTarget.GRADES, false);
            })
        }
        .width('92%')
        .margin({ top: this.topRectHeight + 8, bottom: 16 })

        this.GradesMetrics()

        Text('成绩明细')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .width('92%')
          .margin({ bottom: 8 })

        if (this.grades.length === 0) {
          Column() {
            Text('还没有成绩')
              .fontSize(14)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 40 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        } else {
          Column() {
            ForEach(this.grades, (grade: Grade, index: number) => {
              this.GradeRow(grade)
            }, (grade: Grade, index: number) => `${index}`)
          }
.width('92%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
      }

      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: 100 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    
  }

  @Builder
  GradeRow(grade: Grade) {
    Column() {
      Row() {
        Column() {
          Text(grade.course)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${grade.category} · ${grade.credits} 学分`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 })
          if (grade.detail.length > 0) {
            Text(grade.detail)
              .fontSize(11)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 1 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text(`绩点 ${grade.pointText()}`)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.accent'))
          Text(`成绩 ${grade.scoreText()}`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
        .width(84)
        .alignItems(HorizontalAlign.End)
      }
        .width('100%')
        .padding({ top: 11, bottom: 11 })
        .alignItems(VerticalAlign.Center)

      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor($r('app.color.divider'))
    }
  }

  @Builder
  SettingsContent() {
    Scroll() {
      Column() {
        Text('设置')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: this.topRectHeight + 8, bottom: 16 })

        Column() {
          Row() {
            Text('账号')
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Text(this.hasCredentials ? this.maskAccount(this.savedAccount) : '尚未登录')
              .fontSize(14)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16 })

          Row()
            .width('100%')
            .height(0.5)
            .backgroundColor($r('app.color.divider'))

          Row() {
            Button(this.hasCredentials ? '更换账号' : '登录')
              .height(36)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.accent'))
              .fontSize(13)
              .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
              .onClick(() => {
                this.showLoginForm = true;
              })

            if (this.hasCredentials) {
              Button('退出登录')
                .height(36)
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.danger'))
                .fontSize(13)
                .border({ width: 1, color: $r('app.color.danger'), radius: 6 })
                .margin({ left: 12 })
                .onClick(() => {
                  this.onSignOut();
                })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        }
        .width('92%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)

        // Column() {
        //   Row() {
        //     Text('日志')
        //       .fontSize(15)
        //       .fontColor($r('app.color.text_secondary'))
        //     Blank()
        //     Button('导出日志')
        //       .height(36)
        //       .backgroundColor(Color.Transparent)
        //       .fontColor($r('app.color.accent'))
        //       .fontSize(13)
        //       .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
        //       .onClick(() => {
        //         this.exportLogs();
        //       })
        //   }
        //   .width('100%')
        //   .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        // }
        // .width('92%')
        // .backgroundColor($r('app.color.card_background'))
        // .borderRadius(12)
        // .margin({ top: 12 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: 100 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    
  }

  @Builder
  ManageContent() {
    Scroll() {
      Column() {
        Row() {
          Text('管理')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
          Blank()
          Button('导入课表')
            .height(32)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.accent'))
            .fontSize(13)
            .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
            .onClick(() => {
              if (!this.hasCredentials) {
                this.showLoginForm = true;
                this.currentTarget = LoginTarget.SCHEDULE;
                return;
              }
              this.startPortal(LoginTarget.SCHEDULE, false);
            })
        }
        .width('92%')
        .margin({ top: this.topRectHeight + 8, bottom: 12 })

        Column() {
          Row() {
            Text('学期')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Button('新增学期')
              .height(28)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.accent'))
              .fontSize(12)
              .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
              .onClick(() => {
                this.openSemesterDialog(undefined);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 8 })

          if (this.semesters.length === 0) {
            Text('暂无学期，请先新增或导入')
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 8, bottom: 16 })
              .width('100%')
              .textAlign(TextAlign.Center)
          } else {
            ForEach(this.semesters, (sem: Semester, idx: number) => {
              this.SemesterCard(sem, idx)
            }, (sem: Semester, idx: number) => `sem_${idx}_${sem.dataSemester}`)
          }
        }
        .width('92%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .margin({ bottom: 12 })

        Column() {
          Row() {
            Text('课程')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Button('新增课程')
              .height(28)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.accent'))
              .fontSize(12)
              .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
              .onClick(() => {
                if (this.semesters.length === 0) {
                  this.statusText = '请先新增或导入学期';
                  return;
                }
                this.openCourseDialog(undefined);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 8 })

          Row() {
            Text('当前学期：')
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))
            Text(this.selectedSemesterName())
              .fontSize(12)
              .fontColor($r('app.color.accent'))
              .margin({ left: 4 })
          }
          .width('100%')
          .padding({ left: 16, bottom: 8 })

          if (this.currentManageCourses().length === 0) {
            Text('当前学期暂无课程')
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 8, bottom: 16 })
              .width('100%')
              .textAlign(TextAlign.Center)
          } else {
            ForEach(this.currentManageCourses(), (course: Course, idx: number) => {
              this.ManageCourseCard(course)
            }, (course: Course, idx: number) => `mc_${idx}_${course.id}_${course.colorIndex}`)
          }
        }
        .width('92%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)

        Column() {
          Row() {
            Text('课表')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            Button('导出课表')
              .height(36)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.accent'))
              .fontSize(13)
              .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
              .onClick(() => {
                this.exportIcsSchedule();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        }
        .width('92%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .margin({ top: 12 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ bottom: 100 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    
  }

  private selectedSemesterName(): string {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined) {
      return '无';
    }
    return sem.name;
  }

  private currentManageCourses(): Course[] {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined) {
      return [];
    }
    const out: Course[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      if (this.courses[i].dataSemester === sem.dataSemester) {
        out.push(this.courses[i]);
      }
    }
    return out;
  }

  @Builder
  SemesterCard(sem: Semester, idx: number) {
    Column() {
      Row() {
        Column() {
          Text(sem.name)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.semesterDetailText(sem))
            .fontSize(11)
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.selectedSemesterIndex === idx) {
          Text('当前')
            .fontSize(10)
            .fontColor($r('app.color.accent'))
            .border({ width: 1, color: $r('app.color.accent'), radius: 4 })
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        } else {
          Button('设为当前')
            .height(28)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.accent'))
            .fontSize(12)
            .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
            .onClick(() => {
              this.selectedSemesterIndex = idx;
              this.selectedWeekOffset = 0;
            })
        }

        Button('编辑')
          .height(28)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.text_tertiary'))
          .fontSize(12)
          .border({ width: 1, color: $r('app.color.border_light'), radius: 6 })
          .margin({ left: 6 })
          .onClick(() => {
            this.openSemesterDialog(sem);
          })

        Button('删除')
          .height(28)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.danger'))
          .fontSize(12)
          .border({ width: 1, color: $r('app.color.danger'), radius: 6 })
          .margin({ left: 6 })
          .onClick(() => {
            this.requestDeleteSemester(idx);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })

      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor($r('app.color.divider'))
    }
  }

  private semesterDetailText(sem: Semester): string {
    const weeks: string = sem.weekCount > 0 ? `${sem.weekCount}周` : '未设置';
    const date: string = sem.startDate.length > 0 ? sem.startDate : '未设置第一周';
    return `${date} · ${weeks}`;
  }

  @Builder
  ManageCourseCard(course: Course) {
    Column() {
      Row() {
        Column() {
          Text(course.name)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (course.timeSlots.length > 0) {
            ForEach(course.timeSlots, (slot: TimeSlot, idx: number) => {
              this.SlotDetailGroup(slot, course, idx)
            }, (slot: TimeSlot, idx: number) => `slot_${idx}_${slot.dayOfWeek}_${slot.sectionStart}_${slot.weekRange}`)
          } else {
            Text(course.scheduleText)
              .fontSize(11)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Row()
            .width(24)
            .height(24)
            .borderRadius(12)
            .backgroundColor(course.getColor())
            .border({ width: 2, color: Color.White, radius: 12 })
            .onClick(() => {
              this.colorPickCourse = course;
              this.showCourseColorDialog = true;
            })
            .margin({ bottom: 10 })
          Button('删除')
            .height(28)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.danger'))
            .fontSize(12)
            .border({ width: 1, color: $r('app.color.danger'), radius: 6 })
            .onClick(() => {
              this.requestDeleteCourse(course.id);
            })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })

      Row()
        .width('100%')
        .height(0.5)
        .backgroundColor($r('app.color.divider'))
    }
  }

  @Builder
  SlotDetailGroup(slot: TimeSlot, course: Course, idx: number) {
    Column() {
      ForEach(this.slotDetailLines(slot, course), (line: string, li: number) => {
        Text(line)
          .fontSize(11)
          .fontColor($r('app.color.text_hint'))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: li === 0 ? 0 : 1 })
      }, (line: string, li: number) => `l${li}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: idx === 0 ? 4 : 8 })
  }

  private slotDetailLines(slot: TimeSlot, course: Course): string[] {
    const lines: string[] = [];
    const repeat: string = slot.repeatRule.length > 0 ? `(${slot.repeatRule})` : '';
    lines.push(`${slot.weekRange}周${repeat} ${this.dayLabel(slot.dayOfWeek)} ${slot.sectionStart}-${slot.sectionEnd}节`);
    const campus: string = slot.campus.length > 0 ? slot.campus : '';
    const loc: string = slot.location.length > 0 ? slot.location : course.location;
    const place: string = campus.length > 0 && loc.length > 0 ? `${campus} ${loc}` : (campus + loc);
    if (place.length > 0) {
      lines.push(place);
    }
    if (course.teacher.length > 0) {
      lines.push(`教师：${course.teacher}`);
    }
    return lines;
  }

  private courseTimeSummary(course: Course): string {
    const parts: string[] = [];
    for (let i = 0; i < course.timeSlots.length; i++) {
      const slot: TimeSlot = course.timeSlots[i];
      parts.push(`${this.dayLabel(slot.dayOfWeek)} ${slot.sectionStart}-${slot.sectionEnd}节`);
    }
    return parts.length > 0 ? parts.join('；') : course.scheduleText;
  }

  private dayLabel(day: number): string {
    const labels: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return day >= 1 && day <= 7 ? labels[day] : '';
  }

  private openSemesterDialog(sem: Semester | undefined): void {
    this.editingSemester = sem;
    if (sem === undefined) {
      this.semNameInput = '';
      this.semStartDateInput = '';
      this.semWeekCountInput = '20';
      this.pendingSemDate = new Date();
    } else {
      this.semNameInput = sem.name;
      this.semStartDateInput = sem.startDate;
      this.semWeekCountInput = `${sem.weekCount}`;
      if (sem.startDate.length > 0) {
        this.pendingSemDate = WeekUtils.parseStartDate(sem.startDate);
      } else {
        this.pendingSemDate = new Date();
      }
    }
    this.showSemesterDialog = true;
  }

  private openSemDatePicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(2020, 0, 1),
      end: new Date(2030, 11, 31),
      selected: this.pendingSemDate,
      showTime: false,
      onDateAccept: (value: Date) => {
        this.pendingSemDate = value;
        this.semStartDateInput = WeekUtils.formatDate(WeekUtils.mondayOnOrBefore(value));
      },
    });
  }

  private confirmSemesterDialog(): void {
    const name: string = this.semNameInput.trim();
    if (name.length === 0) {
      this.statusText = '请输入学期名称';
      return;
    }
    const weeks: number = parseInt(this.semWeekCountInput, 10);
    const weekCount: number = isFinite(weeks) && weeks >= 4 ? weeks : 20;
    if (this.editingSemester === undefined) {
      const sem: Semester = new Semester();
      sem.name = name;
      sem.dataSemester = `semester-${Date.now()}`;
      sem.startDate = this.semStartDateInput;
      sem.weekCount = weekCount;
      this.semesters = [...this.semesters, sem];
    } else {
      this.editingSemester.name = name;
      this.editingSemester.startDate = this.semStartDateInput;
      this.editingSemester.weekCount = weekCount;
      const refreshed: Semester[] = [];
      for (let i = 0; i < this.semesters.length; i++) {
        refreshed.push(this.semesters[i]);
      }
      this.semesters = refreshed;
    }
    this.showSemesterDialog = false;
    this.saveCoursesToPref();
  }

  private requestDeleteSemester(idx: number): void {
    this.confirmMessage = `确定删除学期「${this.semesters[idx].name}」及其全部课程吗？`;
    this.confirmTitle = '删除学期';
    this.showConfirmDialog = true;
    const targetIdx: number = idx;
    this.confirmCallback = () => {
      this.deleteSemesterConfirmed(targetIdx);
    };
  }

  private confirmCallback: (() => void) | undefined = undefined;

  private deleteSemesterConfirmed(idx: number): void {
    if (idx < 0 || idx >= this.semesters.length) {
      return;
    }
    const ds: string = this.semesters[idx].dataSemester;
    const remainSems: Semester[] = [];
    for (let i = 0; i < this.semesters.length; i++) {
      if (i !== idx) {
        remainSems.push(this.semesters[i]);
      }
    }
    const remainCourses: Course[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      if (this.courses[i].dataSemester !== ds) {
        remainCourses.push(this.courses[i]);
      }
    }
    this.semesters = remainSems;
    this.courses = remainCourses;
    if (this.selectedSemesterIndex >= this.semesters.length) {
      this.selectedSemesterIndex = this.semesters.length > 0 ? this.semesters.length - 1 : 0;
    }
    this.saveCoursesToPref();
  }

  private openCourseDialog(course: Course | undefined): void {
    this.editingCourse = course;
    if (course === undefined) {
      this.courseNameInput = '';
      this.courseCodeInput = '';
      this.courseTeacherInput = '';
      this.courseLocationInput = '';
      this.courseSlotsInput = '1-16周 周一 1-2节';
      this.courseColorIndex = 0;
    } else {
      this.courseNameInput = course.name;
      this.courseCodeInput = course.code;
      this.courseTeacherInput = course.teacher;
      this.courseLocationInput = course.location;
      this.courseSlotsInput = this.slotsToText(course);
      this.courseColorIndex = course.colorIndex % CoursePresetColors.COLORS.length;
    }
    this.showCourseDialog = true;
  }

  private slotsToText(course: Course): string {
    const parts: string[] = [];
    for (let i = 0; i < course.timeSlots.length; i++) {
      const slot: TimeSlot = course.timeSlots[i];
      const week: string = slot.weekRange.length > 0 ? slot.weekRange : '1-16';
      parts.push(`${week}周 ${this.dayLabel(slot.dayOfWeek)} ${slot.sectionStart}-${slot.sectionEnd}节`);
    }
    return parts.join('\n');
  }

  private confirmCourseDialog(): void {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined) {
      this.statusText = '请先选择学期';
      return;
    }
    const name: string = this.courseNameInput.trim();
    if (name.length === 0) {
      this.statusText = '请输入课程名称';
      return;
    }
    const slots: TimeSlot[] = Course.parseSlotText(this.courseSlotsInput, this.courseLocationInput.trim());
    if (slots.length === 0) {
      this.statusText = '请至少输入一条上课时间';
      return;
    }
    if (this.editingCourse === undefined) {
      const c: Course = new Course();
      c.id = `course-${Date.now()}`;
      c.name = name;
      c.code = this.courseCodeInput.trim();
      c.teacher = this.courseTeacherInput.trim();
      c.location = this.courseLocationInput.trim();
      c.dataSemester = sem.dataSemester;
      c.scheduleText = this.courseSlotsInput;
      c.colorIndex = this.courseColorIndex;
      c.timeSlots = slots;
      this.courses = [...this.courses, c];
    } else {
      this.editingCourse.name = name;
      this.editingCourse.code = this.courseCodeInput.trim();
      this.editingCourse.teacher = this.courseTeacherInput.trim();
      this.editingCourse.location = this.courseLocationInput.trim();
      this.editingCourse.scheduleText = this.courseSlotsInput;
      this.editingCourse.colorIndex = this.courseColorIndex;
      this.editingCourse.timeSlots = slots;
      const refreshed: Course[] = [];
      for (let i = 0; i < this.courses.length; i++) {
        refreshed.push(this.courses[i]);
      }
      this.courses = refreshed;
    }
    this.showCourseDialog = false;
    this.saveCoursesToPref();
  }

  private requestDeleteCourse(id: string): void {
    this.confirmMessage = '确定删除该课程吗？';
    this.confirmTitle = '删除课程';
    this.showConfirmDialog = true;
    const targetId: string = id;
    this.confirmCallback = () => {
      this.deleteCourseConfirmed(targetId);
    };
  }

  private deleteCourseConfirmed(id: string): void {
    const remain: Course[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      if (this.courses[i].id !== id) {
        remain.push(this.courses[i]);
      }
    }
    this.courses = remain;
    this.saveCoursesToPref();
  }

  private async exportIcsSchedule(): Promise<void> {
    const sem: Semester | undefined = this.selectedSemester();
    if (sem === undefined) {
      this.statusText = '请先导入课表';
      return;
    }
    if (sem.startDate.length === 0) {
      this.statusText = '请先设置第一周日期';
      return;
    }
    const ics: string = IcsExport.generate(this.courses, sem, new Date());
    try {
      const docPicker = new picker.DocumentViewPicker();
      const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      saveOptions.newFileNames = [`课表-${sem.name}.ics`];
      saveOptions.fileSuffixChoices = ['ics'];
      const uris: Array<string> = await docPicker.save(saveOptions);
      if (uris.length > 0) {
        const fileUri: string = uris[0];
        const file = fs.openSync(fileUri, fs.OpenMode.WRITE_ONLY);
        fs.writeSync(file.fd, ics);
        fs.closeSync(file);
        this.statusText = '课表已导出为日历文件';
      }
    } catch (e) {
      console.error(`exportIcs failed: ${e}`);
      this.statusText = '导出失败';
    }
  }

  // private async exportLogs(): Promise<void> {
  //   const text: string = AppLogger.exportText();
  //   if (text.length === 0) {
  //     this.statusText = '暂无日志';
  //     return;
  //   }
  //   try {
  //     const docPicker = new picker.DocumentViewPicker();
  //     const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  //     const ts: number = Date.now();
  //     saveOptions.newFileNames = [`aoxiang_log_${ts}.txt`];
  //     saveOptions.fileSuffixChoices = ['txt'];
  //     const uris: Array<string> = await docPicker.save(saveOptions);
  //     if (uris.length > 0) {
  //       const file = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY);
  //       fs.writeSync(file.fd, text);
  //       fs.closeSync(file);
  //       this.statusText = '日志已导出';
  //     }
  //   } catch (e) {
  //     console.error(`exportLogs failed: ${e}`);
  //     this.statusText = '日志导出失败';
  //   }
  // }

  @Builder
  SemesterDialogBuilder() {
    Column() {
      Column() {
        Text(this.editingSemester === undefined ? '新增学期' : '编辑学期')
          .fontSize(18)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 12 })

        TextInput({ placeholder: '学期名称（如 2026-2027秋）', text: this.semNameInput })
          .height(44)
          .fontSize(14)
          .onChange((value: string) => {
            this.semNameInput = value;
          })

        Row() {
          Text(this.semStartDateInput.length > 0 ? `第一周：${this.semStartDateInput}` : '选择第一周日期')
            .fontSize(13)
            .fontColor(this.semStartDateInput.length > 0 ? $r('app.color.text_secondary') : $r('app.color.text_hint'))
            .layoutWeight(1)
            .onClick(() => {
              this.openSemDatePicker();
            })

          Button('选择')
            .height(32)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.accent'))
            .fontSize(13)
            .border({ width: 1, color: $r('app.color.accent'), radius: 6 })
            .onClick(() => {
              this.openSemDatePicker();
            })
        }
        .width('100%')
        .margin({ top: 10 })

        TextInput({ placeholder: '周数（默认20）', text: this.semWeekCountInput })
          .type(InputType.Number)
          .height(44)
          .fontSize(14)
          .margin({ top: 10 })
          .onChange((value: string) => {
            this.semWeekCountInput = value;
          })

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_hint'))
            .fontSize(14)
            .border({ width: 1, color: $r('app.color.border_light'), radius: 8 })
            .onClick(() => {
              this.showSemesterDialog = false;
            })

          Button('保存')
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .fontSize(14)
            .borderRadius(8)
            .margin({ left: 10 })
            .onClick(() => {
              this.confirmSemesterDialog();
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('90%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .padding(22)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.overlay_dim'))
    .zIndex(15)
  }

  @Builder
  CourseDialogBuilder() {
    Column() {
      Column() {
        Text(this.editingCourse === undefined ? '新增课程' : '编辑课程')
          .fontSize(18)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 10 })

        TextInput({ placeholder: '课程名称', text: this.courseNameInput })
          .height(42)
          .fontSize(14)
          .onChange((value: string) => {
            this.courseNameInput = value;
          })

        TextInput({ placeholder: '课程代码（可选）', text: this.courseCodeInput })
          .height(42)
          .fontSize(14)
          .margin({ top: 8 })
          .onChange((value: string) => {
            this.courseCodeInput = value;
          })

        TextInput({ placeholder: '教师（可选）', text: this.courseTeacherInput })
          .height(42)
          .fontSize(14)
          .margin({ top: 8 })
          .onChange((value: string) => {
            this.courseTeacherInput = value;
          })

        TextInput({ placeholder: '上课地点（可选）', text: this.courseLocationInput })
          .height(42)
          .fontSize(14)
          .margin({ top: 8 })
          .onChange((value: string) => {
            this.courseLocationInput = value;
          })

        TextArea({ placeholder: '上课时间（每行一条）\n例如：1-16周 周一 1-2节', text: this.courseSlotsInput })
          .height(92)
          .fontSize(13)
          .margin({ top: 8 })
          .onChange((value: string) => {
            this.courseSlotsInput = value;
          })

        Text('课程颜色')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 10, bottom: 6 })
          .width('100%')

        Row() {
          ForEach(CoursePresetColors.COLORS, (color: string, idx: number) => {
            Column() {
              Row()
                .width(22)
                .height(22)
                .borderRadius(11)
                .backgroundColor(color)
                .border({ width: this.courseColorIndex === idx ? 3 : 0, color: Color.White, radius: 11 })
            }
            .width(32)
            .height(32)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .border({ width: this.courseColorIndex === idx ? 1 : 0, color: $r('app.color.accent'), radius: 16 })
            .onClick(() => {
              this.courseColorIndex = idx;
            })
          }, (color: string, idx: number) => `c_${idx}`)
        }
        .width('100%')
        .margin({ top: 4 })

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_hint'))
            .fontSize(14)
            .border({ width: 1, color: $r('app.color.border_light'), radius: 8 })
            .onClick(() => {
              this.showCourseDialog = false;
            })

          Button('保存')
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .fontSize(14)
            .borderRadius(8)
            .margin({ left: 10 })
            .onClick(() => {
              this.confirmCourseDialog();
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('92%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .padding(20)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.overlay_dim'))
    .zIndex(15)
  }

  @Builder
  ConfirmDialogBuilder() {
    Column() {
      Column() {
        Text(this.confirmTitle)
          .fontSize(18)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Bold)

        Text(this.confirmMessage)
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 10 })
          .textAlign(TextAlign.Center)
          .width('100%')

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_hint'))
            .fontSize(14)
            .border({ width: 1, color: $r('app.color.border_light'), radius: 8 })
            .onClick(() => {
              this.showConfirmDialog = false;
              this.confirmCallback = undefined;
            })

          Button('确定')
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.danger'))
            .fontColor(Color.White)
            .fontSize(14)
            .borderRadius(8)
            .margin({ left: 10 })
            .onClick(() => {
              const cb: (() => void) | undefined = this.confirmCallback;
              this.showConfirmDialog = false;
              this.confirmCallback = undefined;
              if (cb !== undefined) {
                cb();
              }
            })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('86%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .padding(22)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.overlay_dim'))
    .zIndex(15)
  }

  @Builder
  CourseColorDialog() {
    Column() {
      Column() {
        Text('课程颜色')
          .fontSize(17)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 12 })

        ForEach(this.colorRowIndices(), (rowIndices: number[], ri: number) => {
          Row() {
            ForEach(rowIndices, (idx: number) => {
              Column() {
                Row()
                  .width(30)
                  .height(30)
                  .borderRadius(15)
                  .backgroundColor(CoursePresetColors.COLORS[idx])
                  .border({
                    width: this.colorPickCourse !== undefined &&
                      this.colorPickCourse.colorIndex % CoursePresetColors.COLORS.length === idx ? 3 : 0,
                    color: Color.White,
                    radius: 15
                  })
              }
              .width(40)
              .height(40)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .border({
                width: this.colorPickCourse !== undefined &&
                  this.colorPickCourse.colorIndex % CoursePresetColors.COLORS.length === idx ? 1 : 0,
                color: $r('app.color.accent'),
                radius: 20
              })
              .onClick(() => {
                this.changeCourseColor(idx);
              })
            }, (idx: number) => `cc_${ri}_${idx}`)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }, (rowIndices: number[], ri: number) => `crow_${ri}`)

        Row() {
          Button('关闭')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_hint'))
            .fontSize(14)
            .border({ width: 1, color: $r('app.color.border_light'), radius: 8 })
            .onClick(() => {
              this.showCourseColorDialog = false;
              this.colorPickCourse = undefined;
            })
        }
        .width('100%')
        .margin({ top: 16 })
      }
      .width('86%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .padding(22)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.overlay_dim'))
    .zIndex(15)
  }

  private colorRowIndices(): number[][] {
    const rows: number[][] = [];
    const first: number[] = [];
    const second: number[] = [];
    for (let i = 0; i < CoursePresetColors.COLORS.length; i++) {
      if (i < 4) {
        first.push(i);
      } else {
        second.push(i);
      }
    }
    rows.push(first);
    rows.push(second);
    return rows;
  }

  private changeCourseColor(colorIndex: number): void {
    const c: Course | undefined = this.colorPickCourse;
    if (c === undefined) {
      return;
    }
    if (c.colorIndex % CoursePresetColors.COLORS.length === colorIndex) {
      return;
    }
    const newCourse: Course = new Course();
    newCourse.id = c.id;
    newCourse.name = c.name;
    newCourse.code = c.code;
    newCourse.teacher = c.teacher;
    newCourse.scheduleText = c.scheduleText;
    newCourse.location = c.location;
    newCourse.dataSemester = c.dataSemester;
    newCourse.colorIndex = colorIndex;
    newCourse.timeSlots = c.timeSlots;
    const refreshed: Course[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      if (this.courses[i].id === c.id) {
        refreshed.push(newCourse);
      } else {
        refreshed.push(this.courses[i]);
      }
    }
    this.courses = refreshed;
    this.colorPickCourse = newCourse;
    this.saveCoursesToPref();
  }

  @Builder
  WebViewOverlay() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(32)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.showWebView = false;
            this.stopPolling();
          })

        Column() {
          Text(this.currentTarget === LoginTarget.SCHEDULE ? '导入课表' :
            this.currentTarget === LoginTarget.GRADES ? '更新成绩' : '查看电费')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
          Text(this.statusText)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(this.topRectHeight + 56)
      .padding({ top: this.topRectHeight })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.card_background'))

      Progress({ value: this.webProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color($r('app.color.accent'))

      if (!this.interactiveMode) {
        Column() {
          LoadingProgress()
            .width(42)
            .height(42)
            .color($r('app.color.accent'))

          Column() {
            Text('正在通过统一认证' +
              (this.currentTarget === LoginTarget.SCHEDULE ? '导入课表' :
                this.currentTarget === LoginTarget.GRADES ? '更新成绩' : '查看电费'))
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_secondary'))
            Text(this.statusText)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 6 })
          }
          .width('90%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .padding(18)
          .margin({ top: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          Row() {
            Text('请在下方页面完成安全验证')
              .fontSize(13)
              .fontColor($r('app.color.text_tertiary'))
              .layoutWeight(1)

            Button('验证完成')
              .height(32)
              .fontSize(12)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.accent'))
              .borderRadius(6)
              .onClick(() => {
                this.interactiveMode = false;
                this.statusText = '正在继续采集…';
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .alignItems(VerticalAlign.Center)
          .backgroundColor($r('app.color.card_background'))
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.page_background'))
      }

      Web({ src: this.webViewSrc, controller: this.webController })
        .width(this.interactiveMode ? '100%' : 1)
        .height(this.interactiveMode ? '100%' : 1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onlineImageAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .onProgressChange((event: OnProgressChangeEvent) => {
          if (event) {
            this.webProgress = event.newProgress;
            console.info(`WebView progress: ${event.newProgress}`);
          }
        })
        .onPageBegin((event: OnPageBeginEvent) => {
          if (event) {
            console.info(`WebView pageBegin: ${event.url}`);
          }
        })
        .onPageEnd((event: OnPageEndEvent) => {
          if (event) {
            console.info(`WebView pageEnd: ${event.url}`);
          }
        })
        .onErrorReceive((event: OnErrorReceiveEvent) => {
          if (event) {
            console.error(`WebView error: ${event.error.getErrorInfo()} url: ${event.request.getRequestUrl()}`);
          }
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .zIndex(20)
  }

  @Builder
  LoginDialog() {
    Column() {
      Column() {
        Text('账号')
          .fontSize(11)
          .fontColor($r('app.color.accent'))
          .fontWeight(FontWeight.Bold)

        Text('登录教务系统')
          .fontSize(21)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Bold)
          .margin({ top: 4, bottom: 6 })

        Text(this.loginPhase === LoginPhase.CREDENTIALS_ERROR ? '账号或密码不正确，请重新确认' : '使用统一身份认证登录')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))

        Row()
          .width(42)
          .height(3)
          .backgroundColor($r('app.color.accent'))
          .borderRadius(2)
          .margin({ top: 8, bottom: 8 })

        TextInput({ placeholder: '学号', text: this.username })
          .type(InputType.Normal)
          .height(48)
          .fontSize(15)
          .margin({ bottom: 10 })
          .onChange((value: string) => {
            this.username = value;
          })

        TextInput({ placeholder: '统一认证密码', text: this.password })
          .type(InputType.Password)
          .height(48)
          .fontSize(15)
          .onChange((value: string) => {
            this.password = value;
          })

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_hint'))
            .fontSize(14)
            .border({ width: 1, color: $r('app.color.border_light'), radius: 8 })
            .onClick(() => {
              this.showLoginForm = false;
              this.stopPolling();
              this.showWebView = false;
            })

          Button('保存')
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .fontSize(14)
            .borderRadius(8)
            .margin({ left: 10 })
            .onClick(() => {
              this.onSaveCredentials();
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('90%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .padding(22)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.overlay_dim'))
    .zIndex(15)
  }

  @Builder
  SmsDialog() {
    Column() {
      Column() {
        Text('安全验证')
          .fontSize(11)
          .fontColor($r('app.color.accent'))
          .fontWeight(FontWeight.Bold)

        Text('输入短信验证码')
          .fontSize(21)
          .fontColor($r('app.color.text_secondary'))
          .fontWeight(FontWeight.Bold)
          .margin({ top: 4, bottom: 6 })

        Text('验证码已由校方认证系统发送，请输入后继续。')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))

        Row()
          .width(42)
          .height(3)
          .backgroundColor($r('app.color.accent'))
          .borderRadius(2)
          .margin({ top: 8, bottom: 8 })

        TextInput({ placeholder: '短信验证码' })
          .type(InputType.Number)
          .height(48)
          .fontSize(15)
          .onChange((value: string) => {
            this.smsCode = value;
          })

        Row() {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.text_hint'))
            .fontSize(14)
            .border({ width: 1, color: $r('app.color.border_light'), radius: 8 })
            .onClick(() => {
              this.showSmsForm = false;
              this.stopPolling();
              this.showWebView = false;
            })

          Button('验证')
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .fontSize(14)
            .borderRadius(8)
            .margin({ left: 10 })
            .onClick(() => {
              this.onSmsSubmit();
            })
        }
        .width('100%')
        .margin({ top: 12 })
      }
      .width('90%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(16)
      .padding(22)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.overlay_dim'))
    .zIndex(15)
  }
}
