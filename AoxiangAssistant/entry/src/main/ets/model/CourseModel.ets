import { AppLogger } from './AppLogger';

class SlotGroup {
  key: string = '';
  items: TimeSlot[] = [];
}

export class TimeSlot {
  dayOfWeek: number = 0;
  sectionStart: number = 0;
  sectionEnd: number = 0;
  sections: number[] = [];
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
    const secRaw: Object | undefined = obj['sections'];
    if (secRaw !== undefined && secRaw !== null) {
      const secArr: Object[] = secRaw as Object[];
      for (let i = 0; i < secArr.length; i++) {
        s.sections.push(secArr[i] as number);
      }
    }
    if (s.sections.length === 0 && s.sectionStart >= 1) {
      const e: number = s.sectionEnd >= s.sectionStart ? s.sectionEnd : s.sectionStart;
      for (let i = s.sectionStart; i <= e; i++) {
        s.sections.push(i);
      }
    }
    return s;
  }

  toRecord(): Record<string, Object> {
    const secArr: Object[] = [];
    for (let i = 0; i < this.sections.length; i++) {
      secArr.push(this.sections[i]);
    }
    return {
      'dayOfWeek': this.dayOfWeek,
      'sectionStart': this.sectionStart,
      'sectionEnd': this.sectionEnd,
      'sections': secArr,
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
    const slots: TimeSlot[] = Course.parseScheduleSlots(c.scheduleText);
    for (let i = 0; i < slots.length; i++) {
      if (slots[i].location.length === 0) {
        slots[i].location = c.location;
      }
      slots[i].campus = Course.extractCampus(slots[i].location);
    }
    c.timeSlots = slots;
    console.info(`parseScheduleText: text='${c.scheduleText}' slots=${c.timeSlots.length}`);
  }

  static parseSlotText(text: string, defaultLocation: string): TimeSlot[] {
    const slots: TimeSlot[] = Course.parseScheduleSlots(text);
    for (let i = 0; i < slots.length; i++) {
      if (slots[i].location.length === 0) {
        slots[i].location = defaultLocation;
      }
      slots[i].campus = Course.extractCampus(slots[i].location);
    }
    return slots;
  }

  private static parseScheduleSlots(value: string): TimeSlot[] {
    const slots: TimeSlot[] = [];
    if (value === null || value === undefined || value.trim().length === 0) {
      return slots;
    }
    const cleaned: string = value
      .replace(/<[^>]+>/g, ' ')
      .replace(/&nbsp;/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    const segments: string[] = cleaned.split(/[;；]/);
    for (let i = 0; i < segments.length; i++) {
      const segment: string = segments[i].trim();
      if (segment.length === 0 || Course.containsOnline(segment)) {
        AppLogger.info('ScheduleParse', `seg#${i} SKIP empty/online: '${segment}'`);
        continue;
      }
      const day: number = Course.parseDayOfWeek(segment);
      if (day === 0) {
        AppLogger.info('ScheduleParse', `seg#${i} SKIP no-day: '${segment}'`);
        continue;
      }
      const dayPosition: number = Course.findDayPosition(segment);
      const weekPart: string = dayPosition >= 0 ? segment.substring(0, dayPosition) : segment;
      const restPart: string = dayPosition >= 0 ? segment.substring(dayPosition) : segment;
      const sections: number[] = Course.parseSections(restPart);
      if (sections.length === 0) {
        AppLogger.info('ScheduleParse', `seg#${i} SKIP no-sections: '${segment}' rest='${restPart}'`);
        continue;
      }
      const repeatRule: string = Course.parseRepeatRule(segment);
      const weekRanges: string[] = Course.extractWeekRanges(weekPart);
      AppLogger.info('ScheduleParse',
        `seg#${i} day=${day} weekPart='${weekPart}' rest='${restPart}' sections=[${sections.join(',')}] weeks=[${weekRanges.join('|')}] rule='${repeatRule}'`);
      for (let w = 0; w < weekRanges.length; w++) {
        const slot: TimeSlot = new TimeSlot();
        slot.weekRange = weekRanges[w];
        slot.repeatRule = repeatRule;
        slot.dayOfWeek = day;
        slot.sections = sections;
        slot.sectionStart = sections[0];
        slot.sectionEnd = sections[sections.length - 1];
        slots.push(slot);
      }
    }
    const merged: TimeSlot[] = Course.mergeSlots(slots);
    AppLogger.info('ScheduleParse', `value='${value}' rawSlots=${slots.length} mergedSlots=${merged.length}`);
    return merged;
  }

  private static containsOnline(text: string): boolean {
    const keywords: string[] = ['网课', '线上', '在线'];
    for (let i = 0; i < keywords.length; i++) {
      if (text.includes(keywords[i])) {
        return true;
      }
    }
    return false;
  }

  private static parseDayOfWeek(text: string): number {
    const dayMap: Array<[string, number]> = [
      ['周一', 1], ['周二', 2], ['周三', 3], ['周四', 4], ['周五', 5], ['周六', 6], ['周日', 7],
      ['星期一', 1], ['星期二', 2], ['星期三', 3], ['星期四', 4], ['星期五', 5], ['星期六', 6],
      ['星期日', 7], ['星期天', 7],
    ];
    for (let i = 0; i < dayMap.length; i++) {
      if (text.includes(dayMap[i][0])) {
        return dayMap[i][1];
      }
    }
    return 0;
  }

  private static findDayPosition(text: string): number {
    const keys: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日',
      '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日', '星期天'];
    let index: number = -1;
    for (let i = 0; i < keys.length; i++) {
      const found: number = text.indexOf(keys[i]);
      if (found >= 0 && (index < 0 || found < index)) {
        index = found;
      }
    }
    return index;
  }

  private static parseRepeatRule(text: string): string {
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

  private static extractWeekRanges(text: string): string[] {
    const chineseNums: Record<string, number> = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
      '十一': 11, '十二': 12, '十三': 13, '十四': 14, '十五': 15, '十六': 16, '十七': 17,
      '十八': 18, '十九': 19, '二十': 20, '二十一': 21, '二十二': 22,
    };
    let converted: string = text;
    for (const key of Object.keys(chineseNums)) {
      converted = converted.split(`第${key}周`).join(String(chineseNums[key]));
    }
    converted = converted.split('周').join('').trim();
    if (converted.length === 0) {
      console.info(`extractWeekRanges: '${text}' -> ['1-17'] (empty fallback)`);
      return ['1-17'];
    }
    const ranges: string[] = [];
    const parts: string[] = converted.split(/[,，、]/);
    for (let i = 0; i < parts.length; i++) {
      const part: string = parts[i].trim();
      if (part.length === 0) {
        continue;
      }
      const rangeMatch: RegExpMatchArray | null = part.match(/(\d{1,3})[~至\-—](\d{1,3})/);
      if (rangeMatch !== null && rangeMatch.length >= 3) {
        const start: number = Course.parseNum(rangeMatch[1]);
        const end: number = Course.parseNum(rangeMatch[2]);
        if (start > 0 && end >= start) {
          ranges.push(start === end ? `${start}` : `${start}-${end}`);
        }
        continue;
      }
      const singleMatch: RegExpMatchArray | null = part.match(/(\d{1,3})/);
      if (singleMatch !== null && singleMatch.length >= 2) {
        const week: number = Course.parseNum(singleMatch[1]);
        if (week > 0) {
          ranges.push(`${week}`);
        }
      }
    }
    if (ranges.length === 0) {
      console.info(`extractWeekRanges: '${text}' -> ['1-17'] (no ranges)`);
      return ['1-17'];
    }
    console.info(`extractWeekRanges: '${text}' -> [${ranges.join('|')}]`);
    return ranges;
  }

  private static parseSections(text: string): number[] {
    const CHINESE_SECTION_RANGE: RegExp = /第(十一|十二|十三|十四|十五|十六|十七|十八|十九|二十|一|二|三|四|五|六|七|八|九|十)节[~至\-—]?第?(十一|十二|十三|十四|十五|十六|十七|十八|十九|二十|一|二|三|四|五|六|七|八|九|十)?节/;
    const ARABIC_SECTION_RANGE_A: RegExp = /第(\d+)[节~至\-](?:第)?(\d+)节/;
    const ARABIC_SECTION_RANGE_B: RegExp = /(\d+)[节~至\-](\d+)节/;
    const ARABIC_SECTION_LIST: RegExp = /第((?:\d+,)*\d+)节/;
    const ARABIC_SECTION_LIST_B: RegExp = /((?:\d+,)*\d+)节/;
    const CHINESE_SECTION_SINGLE: RegExp = /第(十一|十二|十三|十四|十五|十六|十七|十八|十九|二十|一|二|三|四|五|六|七|八|九|十)节/;
    const ARABIC_SECTION_SINGLE: RegExp = /第(\d+)节/;
    const ARABIC_SECTION_SINGLE_B: RegExp = /(\d+)节/;

    let m: RegExpMatchArray | null = text.match(CHINESE_SECTION_RANGE);
    if (m !== null && m.length >= 3) {
      return Course.sectionRange(Course.chineseNumber(m[1]),
        Course.chineseNumber(m[2] === undefined ? m[1] : m[2]));
    }
    m = text.match(ARABIC_SECTION_RANGE_A);
    if (m !== null && m.length >= 3) {
      return Course.sectionRange(Course.parseNum(m[1]), Course.parseNum(m[2]));
    }
    m = text.match(ARABIC_SECTION_RANGE_B);
    if (m !== null && m.length >= 3) {
      return Course.sectionRange(Course.parseNum(m[1]), Course.parseNum(m[2]));
    }
    m = text.match(ARABIC_SECTION_LIST);
    if (m !== null && m.length >= 2) {
      return Course.parseCsv(m[1]);
    }
    m = text.match(ARABIC_SECTION_LIST_B);
    if (m !== null && m.length >= 2) {
      return Course.parseCsv(m[1]);
    }
    m = text.match(CHINESE_SECTION_SINGLE);
    if (m !== null && m.length >= 2) {
      return [Course.chineseNumber(m[1])];
    }
    m = text.match(ARABIC_SECTION_SINGLE);
    if (m !== null && m.length >= 2) {
      return [Course.parseNum(m[1])];
    }
    m = text.match(ARABIC_SECTION_SINGLE_B);
    if (m !== null && m.length >= 2) {
      return [Course.parseNum(m[1])];
    }
    return [];
  }

  private static sectionRange(start: number, end: number): number[] {
    const out: number[] = [];
    const lo: number = Math.min(start, end);
    const hi: number = Math.max(start, end);
    for (let v = lo; v <= hi; v++) {
      out.push(v);
    }
    return out;
  }

  private static parseCsv(value: string): number[] {
    const out: number[] = [];
    const parts: string[] = value.split(',');
    for (let i = 0; i < parts.length; i++) {
      const parsed: number = Course.parseNum(parts[i].trim());
      if (parsed > 0) {
        out.push(parsed);
      }
    }
    return out;
  }

  private static parseNum(value: string): number {
    if (value === null || value === undefined) {
      return 0;
    }
    const trimmed: string = value.trim();
    if (trimmed.length === 0) {
      return 0;
    }
    const parsed: number = parseInt(trimmed, 10);
    return isNaN(parsed) ? 0 : parsed;
  }

  private static chineseNumber(value: string): number {
    if (value === null || value === undefined) {
      return 0;
    }
    const chineseNums: Record<string, number> = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
      '十一': 11, '十二': 12, '十三': 13, '十四': 14, '十五': 15, '十六': 16, '十七': 17,
      '十八': 18, '十九': 19, '二十': 20, '二十一': 21, '二十二': 22,
    };
    const parsed: number | undefined = chineseNums[value];
    return parsed === undefined ? Course.parseNum(value) : parsed;
  }

  private static mergeSlots(slots: TimeSlot[]): TimeSlot[] {
    const out: TimeSlot[] = [];
    const groupMap: SlotGroup[] = [];
    for (let i = 0; i < slots.length; i++) {
      const slot: TimeSlot = slots[i];
      const key: string = `${slot.dayOfWeek}:${Course.sectionsKey(slot.sections)}:${slot.repeatRule}:${slot.location}`;
      let groupEntry: SlotGroup | undefined = undefined;
      for (let j = 0; j < groupMap.length; j++) {
        if (groupMap[j].key === key) {
          groupEntry = groupMap[j];
          break;
        }
      }
      if (groupEntry === undefined) {
        groupEntry = new SlotGroup();
        groupEntry.key = key;
        groupEntry.items = [];
        groupMap.push(groupEntry);
      }
      groupEntry.items.push(slot);
    }
    for (let g = 0; g < groupMap.length; g++) {
      const intervals: number[][] = [];
      for (let i = 0; i < groupMap[g].items.length; i++) {
        const weeks: number[] = Course.parseListWeeks(groupMap[g].items[i].weekRange);
        if (weeks.length === 0) {
          continue;
        }
        const first: number = weeks[0];
        const last: number = weeks[weeks.length - 1];
        intervals.push([first, last]);
      }
      intervals.sort((a: number[], b: number[]) => a[0] - b[0]);
      const mergedIntervals: number[][] = [];
      for (let i = 0; i < intervals.length; i++) {
        if (mergedIntervals.length === 0) {
          mergedIntervals.push(intervals[i]);
          continue;
        }
        const last: number[] = mergedIntervals[mergedIntervals.length - 1];
        if (intervals[i][0] <= last[1] + 1) {
          last[1] = Math.max(last[1], intervals[i][1]);
        } else {
          mergedIntervals.push(intervals[i]);
        }
      }
      for (let i = 0; i < mergedIntervals.length; i++) {
        const interval: number[] = mergedIntervals[i];
        const base: TimeSlot = groupMap[g].items[0];
        const slot: TimeSlot = new TimeSlot();
        slot.weekRange = interval[0] === interval[1] ? `${interval[0]}` : `${interval[0]}-${interval[1]}`;
        slot.repeatRule = base.repeatRule;
        slot.dayOfWeek = base.dayOfWeek;
        slot.sections = base.sections.slice();
        slot.sectionStart = base.sectionStart;
        slot.sectionEnd = base.sectionEnd;
        slot.location = base.location;
        out.push(slot);
      }
    }
    return out;
  }

  private static sectionsKey(sections: number[]): string {
    return sections.join(',');
  }

  static parseListWeeks(range: string): number[] {
    const weeks: number[] = [];
    if (range === null || range === undefined) {
      return weeks;
    }
    const parts: string[] = range.split(',');
    for (let i = 0; i < parts.length; i++) {
      const part: string = parts[i].trim();
      if (part.length === 0) {
        continue;
      }
      const idx: number = part.indexOf('-');
      let startStr: string;
      let endStr: string;
      if (idx >= 0) {
        startStr = part.substring(0, idx).trim();
        endStr = part.substring(idx + 1).trim();
        if (endStr.length === 0) {
          endStr = '';
        }
      } else {
        startStr = part;
        endStr = '';
      }
      // 严格整数解析（对齐安卓 Integer.parseInt：非纯数字视为解析失败并跳过该段）
      if (!Course.isDigits(startStr)) {
        continue;
      }
      const start: number = parseInt(startStr, 10);
      if (isNaN(start)) {
        continue;
      }
      let end: number = start;
      if (endStr.length > 0) {
        if (!Course.isDigits(endStr)) {
          continue;
        }
        const parsedEnd: number = parseInt(endStr, 10);
        if (isNaN(parsedEnd)) {
          continue;
        }
        end = parsedEnd;
      }
      for (let week = start; week <= end; week++) {
        if (week > 0 && week <= 53) {
          weeks.push(week);
        }
      }
    }
    return weeks;
  }

  private static isDigits(value: string): boolean {
    if (value.length === 0) {
      return false;
    }
    let startIdx: number = 0;
    if (value.charAt(0) === '-') {
      startIdx = 1;
    }
    if (startIdx >= value.length) {
      return false;
    }
    for (let i = startIdx; i < value.length; i++) {
      const ch: string = value.charAt(i);
      if (ch < '0' || ch > '9') {
        return false;
      }
    }
    return true;
  }

  static mergeByName(courses: Course[]): Course[] {
    const order: string[] = [];
    const map: Record<string, Course> = {};
    for (let i = 0; i < courses.length; i++) {
      const c: Course = courses[i];
      const key: string = c.code.length > 0 ? `${c.code.toLowerCase()}|${c.name}` : c.name;
      const existing: Course | undefined = map[key];
      if (existing === undefined) {
        map[key] = c;
        order.push(key);
      } else {
        for (let j = 0; j < c.timeSlots.length; j++) {
          const candidate: TimeSlot = c.timeSlots[j];
          const dup: boolean = existing.timeSlots.some((slot: TimeSlot) =>
            slot.dayOfWeek === candidate.dayOfWeek &&
            Course.sectionsKey(slot.sections) === Course.sectionsKey(candidate.sections) &&
            slot.weekRange === candidate.weekRange &&
            slot.repeatRule === candidate.repeatRule &&
            slot.campus === candidate.campus &&
            slot.location === candidate.location
          );
          if (!dup) {
            existing.timeSlots.push(candidate);
          }
        }
        existing.timeSlots = Course.mergeSlots(existing.timeSlots);
        existing.teacher = Course.mergeTeachers(existing.teacher, c.teacher);
        if (existing.location.length === 0 && c.location.length > 0) {
          existing.location = c.location;
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
      AppLogger.info('MergeByName', `key='${order[i]}' slots=${c.timeSlots.length} teacher='${c.teacher}'`);
    }
    return out;
  }

  private static mergeTeachers(existing: string, incoming: string): string {
    const out: string[] = [];
    const combined: string = existing.length > 0 && incoming.length > 0
      ? existing + ',' + incoming
      : (existing.length > 0 ? existing : incoming);
    const parts: string[] = combined.split(/[,，、;/；|｜\s]+/);
    for (let i = 0; i < parts.length; i++) {
      const name: string = parts[i].trim();
      if (name.length > 0 && !Course.isTeacherMetadata(name) && !out.includes(name)) {
        out.push(name);
      }
      if (out.length >= 15) {
        break;
      }
    }
    return out.join('、');
  }

  private static isTeacherMetadata(value: string): boolean {
    const metaKeywords: string[] = [
      '学科基础', '专业基础', '专业核心', '公共基础', '通识教育',
      '实践实训', '集中实践', '创新创业', '素质拓展', '全校',
      '本科', '研究生', '培养方案', '课程类别', '必修', '选修', '限选', '任选'
    ];
    for (let i = 0; i < metaKeywords.length; i++) {
      if (value.includes(metaKeywords[i])) {
        return true;
      }
    }
    return false;
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
        const weeks: number[] = Course.parseListWeeks(slot.weekRange);
        for (let k = 0; k < weeks.length; k++) {
          if (weeks[k] > maxWeek) {
            maxWeek = weeks[k];
          }
        }
      }
    }
    return maxWeek;
  }
}