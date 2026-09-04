import { Course, Semester, TimeSlot } from './CourseModel';
import { WeekUtils } from './WeekUtils';
import { ScheduleTimes } from './ScheduleTimes';

export class WidgetFormNames {
  static readonly DAILY: string = 'daily_card';
  static readonly TODAY_TOMORROW: string = 'today_tomorrow_card';
  static readonly WEEKLY: string = 'weekly_card';
  static readonly ELECTRICITY: string = 'electricity_card';
}

class WidgetCourseItem {
  time: string = '';
  name: string = '';
  loc: string = '';
  teacher: string = '';
  color: string = '';
  section: string = '';
}

class WidgetDayGroup {
  label: string = '';
  date: string = '';
  courses: WidgetCourseItem[] = [];
}

class SlotRef {
  course: Course | undefined = undefined;
  slot: TimeSlot | undefined = undefined;
}

export class WidgetSnapshot {
  formName: string = '';
  json: string = '';
}

export class WidgetDataBuilder {
  private static readonly DAY_LABELS: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static buildAll(courses: Course[], semesters: Semester[], semesterIndex: number,
                  balance: number, now: Date): WidgetSnapshot[] {
    const out: WidgetSnapshot[] = [];
    out.push(WidgetDataBuilder.snapshot(WidgetFormNames.DAILY,
      WidgetDataBuilder.buildDaily(courses, semesters, semesterIndex, now)));
    out.push(WidgetDataBuilder.snapshot(WidgetFormNames.TODAY_TOMORROW,
      WidgetDataBuilder.buildTodayTomorrow(courses, semesters, semesterIndex, now)));
    out.push(WidgetDataBuilder.snapshot(WidgetFormNames.WEEKLY,
      WidgetDataBuilder.buildWeekly(courses, semesters, semesterIndex, now)));
    out.push(WidgetDataBuilder.snapshot(WidgetFormNames.ELECTRICITY,
      WidgetDataBuilder.buildElectricity(balance, now)));
    return out;
  }

  static emptyAll(now: Date): WidgetSnapshot[] {
    return WidgetDataBuilder.buildAll([], [], 0, -1, now);
  }

  private static snapshot(formName: string, json: string): WidgetSnapshot {
    const snap: WidgetSnapshot = new WidgetSnapshot();
    snap.formName = formName;
    snap.json = json;
    return snap;
  }

  static defaultJson(formName: string): string {
    if (formName === WidgetFormNames.ELECTRICITY) {
      return WidgetDataBuilder.buildElectricity(-1, new Date());
    }
    if (formName === WidgetFormNames.TODAY_TOMORROW) {
      return WidgetDataBuilder.buildTodayTomorrow([], [], 0, new Date());
    }
    if (formName === WidgetFormNames.WEEKLY) {
      return WidgetDataBuilder.buildWeekly([], [], 0, new Date());
    }
    return WidgetDataBuilder.buildDaily([], [], 0, new Date());
  }

  private static activeSemester(semesters: Semester[], semesterIndex: number): Semester | undefined {
    if (semesters.length === 0) {
      return undefined;
    }
    const idx: number = semesterIndex >= 0 && semesterIndex < semesters.length ? semesterIndex : 0;
    return semesters[idx];
  }

  private static currentWeek(sem: Semester | undefined): number {
    if (sem === undefined || sem.startDate.length === 0) {
      return 0;
    }
    return WeekUtils.currentWeek(sem.startDate, sem.weekCount, 0);
  }

  private static hintFor(sem: Semester | undefined, week: number): string {
    if (sem === undefined) {
      return '请先导入课表';
    }
    if (week <= 0) {
      return '请先设置第一周';
    }
    return '';
  }

  private static dayOfWeekFor(date: Date): number {
    const day: number = date.getDay();
    return day === 0 ? 7 : day;
  }

  private static slotCampus(slot: TimeSlot): string {
    return slot.campus.length > 0 ? slot.campus : '长安校区';
  }

  private static coursesForDay(courses: Course[], week: number, day: number, date: Date): WidgetCourseItem[] {
    const items: WidgetCourseItem[] = [];
    if (week <= 0 || day < 1 || day > 7) {
      return items;
    }
    const matched: SlotRef[] = [];
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      for (let j = 0; j < course.timeSlots.length; j++) {
        const slot: TimeSlot = course.timeSlots[j];
        if (slot.dayOfWeek !== day || slot.sectionStart < 1 || slot.sectionEnd < slot.sectionStart) {
          continue;
        }
        if (!WeekUtils.isWeekInRange(week, slot.weekRange)) {
          continue;
        }
        if (!WeekUtils.matchesRepeatRule(week, slot.repeatRule)) {
          continue;
        }
        const ref: SlotRef = new SlotRef();
        ref.course = course;
        ref.slot = slot;
        matched.push(ref);
      }
    }
    matched.sort((a: SlotRef, b: SlotRef) => {
      const sa: number = a.slot !== undefined ? a.slot.sectionStart : 99;
      const sb: number = b.slot !== undefined ? b.slot.sectionStart : 99;
      return sa - sb;
    });
    for (let i = 0; i < matched.length; i++) {
      const ref: SlotRef = matched[i];
      if (ref.course === undefined || ref.slot === undefined) {
        continue;
      }
      const course: Course = ref.course;
      const slot: TimeSlot = ref.slot;
      const item: WidgetCourseItem = new WidgetCourseItem();
      item.name = course.name;
      item.time = ScheduleTimes.timeSpanFor(WidgetDataBuilder.slotCampus(slot), date,
        slot.sectionStart, slot.sectionEnd);
      item.section = slot.sectionEnd > slot.sectionStart
        ? `${slot.sectionStart}-${slot.sectionEnd}节`
        : `${slot.sectionStart}节`;
      item.loc = slot.location.length > 0 ? slot.location : course.location;
      item.teacher = course.teacher;
      item.color = course.getColor();
      items.push(item);
    }
    return items;
  }

  private static dayGroup(courses: Course[], week: number, date: Date, label: string): WidgetDayGroup {
    const group: WidgetDayGroup = new WidgetDayGroup();
    const day: number = WidgetDataBuilder.dayOfWeekFor(date);
    group.label = label.length > 0 ? label : WidgetDataBuilder.DAY_LABELS[day];
    group.date = WeekUtils.formatMD(date);
    group.courses = WidgetDataBuilder.coursesForDay(courses, week, day, date);
    return group;
  }

  private static courseItemRecord(item: WidgetCourseItem): Record<string, Object> {
    return {
      'time': item.time,
      'section': item.section,
      'name': item.name,
      'loc': item.loc,
      'teacher': item.teacher,
      'color': item.color,
    };
  }

  private static courseItemArray(items: WidgetCourseItem[]): Object[] {
    const arr: Object[] = [];
    for (let i = 0; i < items.length; i++) {
      arr.push(WidgetDataBuilder.courseItemRecord(items[i]));
    }
    return arr;
  }

  private static dayGroupRecord(group: WidgetDayGroup): Record<string, Object> {
    return {
      'label': group.label,
      'date': group.date,
      'empty': group.courses.length === 0,
      'courses': WidgetDataBuilder.courseItemArray(group.courses),
    };
  }

  private static buildDaily(courses: Course[], semesters: Semester[], semesterIndex: number,
                            now: Date): string {
    const sem: Semester | undefined = WidgetDataBuilder.activeSemester(semesters, semesterIndex);
    const week: number = WidgetDataBuilder.currentWeek(sem);
    const group: WidgetDayGroup = WidgetDataBuilder.dayGroup(courses, week, now, '今天');
    const payload: Record<string, Object> = {
      'title': week > 0 ? `第${week}周 ${group.label}` : '今日课表',
      'date': group.date,
      'hint': WidgetDataBuilder.hintFor(sem, week),
      'empty': group.courses.length === 0,
      'courses': WidgetDataBuilder.courseItemArray(group.courses),
    };
    return JSON.stringify(payload);
  }

  private static buildTodayTomorrow(courses: Course[], semesters: Semester[], semesterIndex: number,
                                    now: Date): string {
    const sem: Semester | undefined = WidgetDataBuilder.activeSemester(semesters, semesterIndex);
    const tomorrow: Date = new Date(now.getTime() + 24 * 60 * 60 * 1000);
    const weekToday: number = WidgetDataBuilder.currentWeek(sem);
    let weekTomorrow: number = weekToday;
    if (sem !== undefined && sem.startDate.length > 0) {
      weekTomorrow = WeekUtils.weekNumberForDate(tomorrow, sem.startDate);
      if (weekTomorrow < 1) {
        weekTomorrow = weekToday;
      }
    }
    const groups: Object[] = [];
    groups.push(WidgetDataBuilder.dayGroupRecord(
      WidgetDataBuilder.dayGroup(courses, weekToday, now, '今天')));
    groups.push(WidgetDataBuilder.dayGroupRecord(
      WidgetDataBuilder.dayGroup(courses, weekTomorrow, tomorrow, '明天')));
    const payload: Record<string, Object> = {
      'title': weekToday > 0 ? `第${weekToday}周` : '今明课表',
      'hint': WidgetDataBuilder.hintFor(sem, weekToday),
      'days': groups,
    };
    return JSON.stringify(payload);
  }

  private static buildWeekly(courses: Course[], semesters: Semester[], semesterIndex: number,
                             now: Date): string {
    const sem: Semester | undefined = WidgetDataBuilder.activeSemester(semesters, semesterIndex);
    const week: number = WidgetDataBuilder.currentWeek(sem);
    const groups: Object[] = [];
    let total: number = 0;
    const todayDay: number = WidgetDataBuilder.dayOfWeekFor(now);
    let weekStart: Date = now;
    if (sem !== undefined && sem.startDate.length > 0 && week > 0) {
      weekStart = WeekUtils.weekStart(sem.startDate, week);
    } else {
      weekStart = new Date(now.getTime() - (todayDay - 1) * 24 * 60 * 60 * 1000);
    }
    for (let i = 0; i < 7; i++) {
      const date: Date = new Date(weekStart.getTime() + i * 24 * 60 * 60 * 1000);
      const group: WidgetDayGroup = WidgetDataBuilder.dayGroup(courses, week, date,
        WidgetDataBuilder.DAY_LABELS[i + 1]);
      total += group.courses.length;
      const record: Record<string, Object> = WidgetDataBuilder.dayGroupRecord(group);
      record['today'] = (i + 1) === todayDay;
      groups.push(record);
    }
    const payload: Record<string, Object> = {
      'title': week > 0 ? `第${week}周课表` : '每周课表',
      'hint': WidgetDataBuilder.hintFor(sem, week),
      'empty': total === 0,
      'days': groups,
    };
    return JSON.stringify(payload);
  }

  private static buildElectricity(balance: number, now: Date): string {
    const ok: boolean = balance >= 0;
    const payload: Record<string, Object> = {
      'value': ok ? balance.toFixed(2) : '--',
      'unit': '元',
      'empty': !ok,
      'hint': ok ? '' : '打开应用查询电费',
      'updated': ok ? WidgetDataBuilder.timeLabel(now) : '',
    };
    return JSON.stringify(payload);
  }

  private static timeLabel(date: Date): string {
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const hour: number = date.getHours();
    const minute: number = date.getMinutes();
    const hh: string = hour < 10 ? `0${hour}` : `${hour}`;
    const mm: string = minute < 10 ? `0${minute}` : `${minute}`;
    return `${month}/${day} ${hh}:${mm}`;
  }
}
