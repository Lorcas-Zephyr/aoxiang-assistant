export class TimeSlot {
  dayOfWeek: number = 0;
  sectionStart: number = 0;
  sectionEnd: number = 0;
  weekRange: string = '';
  repeatRule: string = '';
  campus: string = '';
  location: string = '';

  static fromJsObject(obj: Record<string, Object>): TimeSlot {
    const s: TimeSlot = new TimeSlot();
    const d: Object | undefined = obj['dayOfWeek'];
    s.dayOfWeek = d !== undefined && d !== null ? (d as number) : 0;
    const ss: Object | undefined = obj['sectionStart'];
    s.sectionStart = ss !== undefined && ss !== null ? (ss as number) : 0;
    const se: Object | undefined = obj['sectionEnd'];
    s.sectionEnd = se !== undefined && se !== null ? (se as number) : 0;
    const wr: Object | undefined = obj['weekRange'];
    s.weekRange = wr !== undefined && wr !== null ? (wr as string) : '';
    const rr: Object | undefined = obj['repeatRule'];
    s.repeatRule = rr !== undefined && rr !== null ? (rr as string) : '';
    const cp: Object | undefined = obj['campus'];
    s.campus = cp !== undefined && cp !== null ? (cp as string) : '';
    const loc: Object | undefined = obj['location'];
    s.location = loc !== undefined && loc !== null ? (loc as string) : '';
    return s;
  }

  toRecord(): Record<string, Object> {
    return {
      'dayOfWeek': this.dayOfWeek,
      'sectionStart': this.sectionStart,
      'sectionEnd': this.sectionEnd,
      'weekRange': this.weekRange,
      'repeatRule': this.repeatRule,
      'campus': this.campus,
      'location': this.location,
    };
  }
}

export class Course {
  id: string = '';
  name: string = '';
  code: string = '';
  teacher: string = '';
  scheduleText: string = '';
  location: string = '';
  dataSemester: string = '';
  colorIndex: number = 0;
  timeSlots: TimeSlot[] = [];

  displayDay(): string {
    const labels: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (this.timeSlots.length === 0) {
      return '';
    }
    const day: number = this.timeSlots[0].dayOfWeek;
    return day >= 1 && day <= 7 ? labels[day] : '';
  }

  displaySection(): string {
    if (this.timeSlots.length === 0) {
      return this.scheduleText;
    }
    const slot: TimeSlot = this.timeSlots[0];
    if (slot.sectionStart > 0 && slot.sectionEnd > 0) {
      return `第${slot.sectionStart}-${slot.sectionEnd}节`;
    }
    return this.scheduleText;
  }

  getColor(): string {
    return CoursePresetColors.COLORS[this.colorIndex % CoursePresetColors.COLORS.length];
  }

  sectionSpan(): number {
    if (this.timeSlots.length === 0) {
      return 1;
    }
    const slot: TimeSlot = this.timeSlots[0];
    if (slot.sectionStart > 0 && slot.sectionEnd >= slot.sectionStart) {
      return slot.sectionEnd - slot.sectionStart + 1;
    }
    return 1;
  }

  static fromJsObject(obj: Record<string, Object>): Course {
    const c: Course = new Course();
    const idVal: Object | undefined = obj['id'];
    c.id = idVal !== undefined && idVal !== null ? (idVal as string) : '';
    c.name = (obj['name'] ?? '') as string;
    c.code = (obj['code'] ?? '') as string;
    c.teacher = (obj['teacher'] ?? '') as string;
    c.scheduleText = (obj['scheduleText'] ?? '') as string;
    c.location = (obj['location'] ?? '') as string;
    c.dataSemester = (obj['dataSemester'] ?? '') as string;
    const ci: Object | undefined = obj['colorIndex'];
    c.colorIndex = ci !== undefined && ci !== null ? (ci as number) : 0;
    const tsRaw: Object | undefined = obj['timeSlots'];
    if (tsRaw !== undefined && tsRaw !== null) {
      const tsArr: Object[] = tsRaw as Object[];
      for (let i = 0; i < tsArr.length; i++) {
        c.timeSlots.push(TimeSlot.fromJsObject(tsArr[i] as Record<string, Object>));
      }
    }
    if (c.timeSlots.length === 0) {
      Course.migrateLegacyCourse(c, obj);
    }
    if (c.timeSlots.length === 0) {
      Course.parseScheduleText(c);
    }
    if (c.id.length === 0) {
      c.id = `course-${c.dataSemester}-${c.name}-${c.code}`;
    }
    return c;
  }

  private static migrateLegacyCourse(c: Course, obj: Record<string, Object>): void {
    const slot: TimeSlot = new TimeSlot();
    const d: Object | undefined = obj['dayOfWeek'];
    slot.dayOfWeek = d !== undefined && d !== null ? (d as number) : 0;
    const ss: Object | undefined = obj['sectionStart'];
    slot.sectionStart = ss !== undefined && ss !== null ? (ss as number) : 0;
    const se: Object | undefined = obj['sectionEnd'];
    slot.sectionEnd = se !== undefined && se !== null ? (se as number) : 0;
    const wr: Object | undefined = obj['weekRange'];
    slot.weekRange = wr !== undefined && wr !== null ? (wr as string) : '';
    const rr: Object | undefined = obj['repeatRule'];
    slot.repeatRule = rr !== undefined && rr !== null ? (rr as string) : '';
    const cp: Object | undefined = obj['campus'];
    slot.campus = cp !== undefined && cp !== null ? (cp as string) : '';
    slot.location = c.location;
    if (slot.dayOfWeek >= 1 && slot.sectionStart >= 1) {
      c.timeSlots.push(slot);
    }
  }

  static parseScheduleText(c: Course): void {
    if (c.scheduleText.length === 0) {
      return;
    }
    const segments: string[] = c.scheduleText.split(/[;；]/);
    for (let i = 0; i < segments.length; i++) {
      const seg: string = segments[i].trim();
      if (seg.length === 0) {
        continue;
      }
      const slot: TimeSlot = new TimeSlot();
      slot.weekRange = Course.extractWeekRanges(seg);
      slot.repeatRule = Course.extractRepeatRule(seg);
      slot.campus = Course.extractCampus(seg + ' ' + c.location);
      const dayMap: Record<string, number> = {
        '周一': 1, '周二': 2, '周三': 3, '周四': 4,
        '周五': 5, '周六': 6, '周日': 7, '周天': 7,
        '星期一': 1, '星期二': 2, '星期三': 3, '星期四': 4,
        '星期五': 5, '星期六': 6, '星期日': 7,
      };
      for (const key of Object.keys(dayMap)) {
        if (seg.includes(key)) {
          slot.dayOfWeek = dayMap[key];
          break;
        }
      }
      const sectionMatchA: RegExpMatchArray | null = seg.match(/[第]?\s*(\d+)\s*[-–—~至]\s*(\d+)\s*节/);
      if (sectionMatchA !== null && sectionMatchA.length >= 3) {
        slot.sectionStart = parseInt(sectionMatchA[1], 10);
        slot.sectionEnd = parseInt(sectionMatchA[2], 10);
      } else {
        const sectionMatchB: RegExpMatchArray | null = seg.match(/[第]?\s*(\d+)\s*[-–—~至]\s*(\d+)/);
        if (sectionMatchB !== null && sectionMatchB.length >= 3) {
          slot.sectionStart = parseInt(sectionMatchB[1], 10);
          slot.sectionEnd = parseInt(sectionMatchB[2], 10);
        }
      }
      slot.location = c.location;
      if (slot.dayOfWeek >= 1 && slot.dayOfWeek <= 7 && slot.sectionStart >= 1) {
        c.timeSlots.push(slot);
      }
    }
    console.info(`parseScheduleText: text='${c.scheduleText}' slots=${c.timeSlots.length}`);
  }

  private static extractRepeatRule(text: string): string {
    if (text.includes('单周') || text.includes('(单)') || text.includes('（单）')) {
      return '仅单周';
    }
    if (text.includes('双周') || text.includes('(双)') || text.includes('（双）')) {
      return '仅双周';
    }
    return '';
  }

  private static extractCampus(text: string): string {
    if (text.includes('长安校区')) {
      return '长安校区';
    }
    if (text.includes('友谊校区')) {
      return '友谊校区';
    }
    if (text.includes('太仓校区')) {
      return '太仓校区';
    }
    return '';
  }

  private static extractWeekRanges(text: string): string {
    const chineseNums: Record<string, string> = {
      '一': '1', '二': '2', '三': '3', '四': '4', '五': '5', '六': '6', '七': '7', '八': '8',
      '九': '9', '十': '10', '十一': '11', '十二': '12', '十三': '13', '十四': '14',
      '十五': '15', '十六': '16', '十七': '17', '十八': '18', '十九': '19', '二十': '20',
      '二十一': '21', '二十二': '22',
    };
    let converted: string = text;
    for (const key of Object.keys(chineseNums)) {
      converted = converted.split(`第${key}周`).join(chineseNums[key]);
    }
    const weekPart: string = converted.replace(/周/g, ' ').trim();
    const ranges: string[] = [];
    const segments: string[] = weekPart.split(/[,，、\s]+/);
    for (let i = 0; i < segments.length; i++) {
      const seg: string = segments[i].trim();
      if (seg.length === 0) {
        continue;
      }
      const rangeMatch: RegExpMatchArray | null = seg.match(/^(\d+)\s*[-~至—]\s*(\d+)$/);
      if (rangeMatch !== null && rangeMatch.length >= 3) {
        const start: number = parseInt(rangeMatch[1], 10);
        const end: number = parseInt(rangeMatch[2], 10);
        if (start > 0 && end >= start) {
          ranges.push(start === end ? `${start}` : `${start}-${end}`);
        }
        continue;
      }
      const singleMatch: RegExpMatchArray | null = seg.match(/^(\d+)$/);
      if (singleMatch !== null && singleMatch.length >= 2) {
        const week: number = parseInt(singleMatch[1], 10);
        if (week > 0) {
          ranges.push(`${week}`);
        }
      }
    }
    if (ranges.length === 0) {
      return '1-16';
    }
    return Course.mergeRanges(ranges);
  }

  private static mergeRanges(ranges: string[]): string {
    const nums: number[] = [];
    for (let i = 0; i < ranges.length; i++) {
      const bounds: string[] = ranges[i].split('-');
      const start: number = parseInt(bounds[0], 10);
      const end: number = bounds.length >= 2 ? parseInt(bounds[1], 10) : start;
      for (let w = start; w <= end; w++) {
        if (!nums.includes(w)) {
          nums.push(w);
        }
      }
    }
    nums.sort((a: number, b: number) => a - b);
    const merged: string[] = [];
    let runStart: number = nums[0];
    let runEnd: number = nums[0];
    for (let i = 1; i < nums.length; i++) {
      if (nums[i] === runEnd + 1) {
        runEnd = nums[i];
      } else {
        merged.push(runStart === runEnd ? `${runStart}` : `${runStart}-${runEnd}`);
        runStart = nums[i];
        runEnd = nums[i];
      }
    }
    merged.push(runStart === runEnd ? `${runStart}` : `${runStart}-${runEnd}`);
    return merged.join(',');
  }

  static parseSlotText(text: string, defaultLocation: string): TimeSlot[] {
    const slots: TimeSlot[] = [];
    if (text.length === 0) {
      return slots;
    }
    const segments: string[] = text.split(/[;；\n]/);
    for (let i = 0; i < segments.length; i++) {
      const seg: string = segments[i].trim();
      if (seg.length === 0) {
        continue;
      }
      const slot: TimeSlot = new TimeSlot();
      slot.weekRange = Course.extractWeekRanges(seg);
      slot.repeatRule = Course.extractRepeatRule(seg);
      slot.campus = Course.extractCampus(seg + ' ' + defaultLocation);
      slot.location = defaultLocation;
      const dayMap: Record<string, number> = {
        '周一': 1, '周二': 2, '周三': 3, '周四': 4,
        '周五': 5, '周六': 6, '周日': 7, '周天': 7,
        '星期一': 1, '星期二': 2, '星期三': 3, '星期四': 4,
        '星期五': 5, '星期六': 6, '星期日': 7,
      };
      for (const key of Object.keys(dayMap)) {
        if (seg.includes(key)) {
          slot.dayOfWeek = dayMap[key];
          break;
        }
      }
      const sectionMatchA: RegExpMatchArray | null = seg.match(/[第]?\s*(\d+)\s*[-–—~至]\s*(\d+)\s*节/);
      if (sectionMatchA !== null && sectionMatchA.length >= 3) {
        slot.sectionStart = parseInt(sectionMatchA[1], 10);
        slot.sectionEnd = parseInt(sectionMatchA[2], 10);
      } else {
        const sectionMatchB: RegExpMatchArray | null = seg.match(/[第]?\s*(\d+)\s*[-–—~至]\s*(\d+)/);
        if (sectionMatchB !== null && sectionMatchB.length >= 3) {
          slot.sectionStart = parseInt(sectionMatchB[1], 10);
          slot.sectionEnd = parseInt(sectionMatchB[2], 10);
        }
      }
      if (slot.dayOfWeek >= 1 && slot.dayOfWeek <= 7 && slot.sectionStart >= 1) {
        slots.push(slot);
      }
    }
    return slots;
  }

  static mergeByName(courses: Course[]): Course[] {
    const order: string[] = [];
    const map: Record<string, Course> = {};
    for (let i = 0; i < courses.length; i++) {
      const c: Course = courses[i];
      const key: string = c.code.length > 0 ? `${c.code}|${c.name}` : c.name;
      const existing: Course | undefined = map[key];
      if (existing === undefined) {
        map[key] = c;
        order.push(key);
      } else {
        for (let j = 0; j < c.timeSlots.length; j++) {
          const candidate: TimeSlot = c.timeSlots[j];
          const dup: boolean = existing.timeSlots.some((slot: TimeSlot) =>
            slot.dayOfWeek === candidate.dayOfWeek &&
            slot.sectionStart === candidate.sectionStart &&
            slot.sectionEnd === candidate.sectionEnd &&
            slot.weekRange === candidate.weekRange &&
            slot.repeatRule === candidate.repeatRule &&
            slot.campus === candidate.campus &&
            slot.location === candidate.location
          );
          if (!dup) {
            existing.timeSlots.push(candidate);
          }
        }
        if (existing.teacher.length === 0 && c.teacher.length > 0) {
          existing.teacher = c.teacher;
        }
      }
    }
    const out: Course[] = [];
    for (let i = 0; i < order.length; i++) {
      const c: Course = map[order[i]];
      c.colorIndex = i % CoursePresetColors.COLORS.length;
      if (c.id.length === 0) {
        c.id = `course-${c.dataSemester}-${c.name}-${c.code}`;
      }
      out.push(c);
    }
    return out;
  }

  toRecord(): Record<string, Object> {
    const tsArr: Object[] = [];
    for (let i = 0; i < this.timeSlots.length; i++) {
      tsArr.push(this.timeSlots[i].toRecord());
    }
    const obj: Record<string, Object> = {
      'id': this.id,
      'name': this.name,
      'code': this.code,
      'teacher': this.teacher,
      'scheduleText': this.scheduleText,
      'location': this.location,
      'dataSemester': this.dataSemester,
      'colorIndex': this.colorIndex,
      'timeSlots': tsArr,
    };
    return obj;
  }

  static fromRecord(obj: Record<string, Object>): Course {
    return Course.fromJsObject(obj);
  }
}

export class CoursePresetColors {
  static readonly COLORS: string[] = [
    '#E53935', '#1E88E5', '#43A047', '#FB8C00',
    '#8E24AA', '#00ACC1', '#FFB300', '#3949AB',
  ];
}

export class Semester {
  name: string = '';
  dataSemester: string = '';
  startDate: string = '';
  weekCount: number = 20;

  static fromJsObject(obj: Record<string, Object>): Semester {
    const s: Semester = new Semester();
    s.name = (obj['name'] ?? '') as string;
    s.dataSemester = (obj['dataSemester'] ?? '') as string;
    const sd: Object | undefined = obj['startDate'];
    s.startDate = sd !== undefined && sd !== null ? (sd as string) : '';
    const wc: Object | undefined = obj['weekCount'];
    s.weekCount = wc !== undefined && wc !== null ? (wc as number) : 20;
    return s;
  }

  toRecord(): Record<string, Object> {
    return { 'name': this.name, 'dataSemester': this.dataSemester, 'startDate': this.startDate, 'weekCount': this.weekCount };
  }

  static computeWeekCount(courses: Course[]): number {
    let maxWeek: number = 20;
    for (let i = 0; i < courses.length; i++) {
      const course: Course = courses[i];
      for (let j = 0; j < course.timeSlots.length; j++) {
        const slot: TimeSlot = course.timeSlots[j];
        const bounds: string[] = slot.weekRange.split(',');
        for (let k = 0; k < bounds.length; k++) {
          const parts: string[] = bounds[k].split('-');
          const end: number = parseInt(parts.length >= 2 ? parts[1] : parts[0], 10);
          if (isFinite(end) && end > maxWeek) {
            maxWeek = end;
          }
        }
      }
    }
    return maxWeek;
  }
}