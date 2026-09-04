import webview from '@ohos.web.webview';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { CredentialStore } from '../model/CredentialStore';
import { Grade, GradeMath } from '../model/GradeModel';
import { Course, CoursePresetColors, Semester } from '../model/CourseModel';
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
  @State courses: Course[] = [];
  @State semesters: Semester[] = [];
  @State selectedSemesterIndex: number = 0;

  private webController: webview.WebviewController = new webview.WebviewController();
  private tabsController: TabsController = new TabsController();
  private credentialStore: CredentialStore = new CredentialStore();
  private autoCollectScript: string = '';
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
      console.error('Failed to load auto_collect.js');
    }
  }

  private async refreshCredentialState(): Promise<void> {
    this.hasCredentials = this.credentialStore.hasCredentials();
    if (this.hasCredentials) {
      const creds: string[] = await this.credentialStore.readCredentials();
      this.savedAccount = creds[0];
      this.username = creds[0];
      this.password = creds[1];
    } else {
      this.savedAccount = '';
    }
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
      this.assignCourseColors();
      if (this.selectedSemesterIndex >= this.semesters.length) {
        this.selectedSemesterIndex = 0;
      }
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
      const dayA: number = dayOrder.indexOf(a.dayOfWeek);
      const dayB: number = dayOrder.indexOf(b.dayOfWeek);
      if (dayA !== dayB) {
        return dayA - dayB;
      }
      return a.sectionStart - b.sectionStart;
    });
    return out;
  }

  private weightedPoint(): string {
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
    this.statusText = '已退出登录';
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
      .replace('__CAN_FILL_SMS__', canFillSms.toString());
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
          this.handleCollectedGrades(obj['rows']);
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
      if (phase === LoginPhase.WAITING) {
        this.statusText = '正在查找目标页面…';
        return;
      }
    } catch (e) {
      console.error(`handleJsResult exception: ${e}`);
      this.statusText = '正在等待页面加载…';
    }
  }

  private handleCollectedGrades(rowsObj: Object | undefined): void {
    console.info(`handleCollectedGrades called, rowsObj type=${typeof rowsObj}`);
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
    if (couRaw.length === 0) {
      this.stopPolling();
      this.showWebView = false;
      this.statusText = '没有解析到课表数据';
      return;
    }
    const semOut: Semester[] = [];
    for (let i = 0; i < semRaw.length; i++) {
      semOut.push(Semester.fromJsObject(semRaw[i] as Record<string, Object>));
    }
    const couOut: Course[] = [];
    for (let i = 0; i < couRaw.length; i++) {
      couOut.push(Course.fromRecord(couRaw[i] as Record<string, Object>));
    }
    this.semesters = semOut;
    this.courses = couOut;
    this.assignCourseColors();
    this.saveCoursesToPref();
    this.selectedSemesterIndex = 0;
    this.stopPolling();
    this.showWebView = false;
    this.statusText = `已导入 ${couOut.length} 门课程`;
    this.currentTab = 1;
    this.tabsController.changeIndex(1);
    console.info(`handleCollectedSchedule: DONE, courses=${this.courses.length} semesters=${this.semesters.length}`);
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
          this.SettingsContent()
        }
        .tabBar('')
      }
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .barBackgroundColor(Color.Transparent)
      .barHeight(0)

      this.FloatingTabBar()

      if (this.showWebView) {
        this.WebViewOverlay()
      }

      if (this.showLoginForm) {
        this.LoginDialog()
      }

      if (this.showSmsForm) {
        this.SmsDialog()
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
        { 'label': '设置', 'index': 3 },
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
    .translate({ y: -24 })
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
          .margin({ top: 40, bottom: 8 })

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
      .margin({ top: 20, bottom: 12 })

      if (this.courses.length === 0) {
        Column() {
          Text('还没有课表数据')
            .fontSize(14)
            .fontColor($r('app.color.text_hint'))
            .margin({ top: 40 })
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
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
      } else {
        if (this.semesters.length > 1) {
          Row() {
            Button('‹')
              .fontSize(18)
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.accent'))
              .border({ width: 1, color: $r('app.color.border_light'), radius: 6 })
              .onClick(() => {
                if (this.selectedSemesterIndex > 0) {
                  this.selectedSemesterIndex--;
                }
              })
            Text(this.semesters[this.selectedSemesterIndex].name)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Button('›')
              .fontSize(18)
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.accent'))
              .border({ width: 1, color: $r('app.color.border_light'), radius: 6 })
              .onClick(() => {
                if (this.selectedSemesterIndex < this.semesters.length - 1) {
                  this.selectedSemesterIndex++;
                }
              })
          }
          .width('92%')
          .margin({ bottom: 12 })
        }

        Column() {
          ScheduleGrid({ courses: this.currentSemesterCourses() })
        }
        .width('92%')
        .backgroundColor($r('app.color.schedule_bg'))
        .borderRadius(12)
        .padding(8)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
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
        .margin({ top: 20, bottom: 16 })

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
          .padding({ left: 14, right: 14 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
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
          .margin({ top: 20, bottom: 16 })

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
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
      .height(56)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.card_background'))

      Progress({ value: this.webProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .color($r('app.color.accent'))

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

      Web({ src: this.webViewSrc, controller: this.webController })
        .width(1)
        .height(1)
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
  }
}
