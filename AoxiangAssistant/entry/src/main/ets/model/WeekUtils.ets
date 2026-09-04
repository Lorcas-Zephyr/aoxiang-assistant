export class WeekUtils {
  private static readonly DAY_MS: number = 24 * 60 * 60 * 1000;
  private static readonly WEEK_MS: number = 7 * 24 * 60 * 60 * 1000;

  static parseWeeks(range: string): number[] {
    const weeks: number[] = [];
    if (range.length === 0) {
      for (let w = 1; w <= 16; w++) {
        weeks.push(w);
      }
      console.info(`parseWeeks: range='' => weeks=[1..16] count=16`);
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
        if (!WeekUtils.isDigits(part)) {
          continue;
        }
        startStr = part;
        endStr = '';
      }
      if (!WeekUtils.isDigits(startStr)) {
        continue;
      }
      const start: number = parseInt(startStr, 10);
      if (isNaN(start)) {
        continue;
      }
      let end: number = start;
      if (endStr.length > 0) {
        if (!WeekUtils.isDigits(endStr)) {
          continue;
        }
        const parsedEnd: number = parseInt(endStr, 10);
        if (isNaN(parsedEnd)) {
          continue;
        }
        end = parsedEnd;
      }
      for (let w = start; w <= end; w++) {
        if (w > 0 && w <= 53) {
          weeks.push(w);
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

  static isWeekInRange(week: number, range: string): boolean {
    return WeekUtils.parseWeeks(range).includes(week);
  }

  static matchesRepeatRule(week: number, rule: string): boolean {
    if (rule === '仅单周') {
      return week % 2 === 1;
    }
    if (rule === '仅双周') {
      return week % 2 === 0;
    }
    return true;
  }

  static mondayOnOrBefore(d: Date): Date {
    const day: number = d.getDay();
    const offset: number = day === 0 ? 6 : day - 1;
    return new Date(d.getTime() - offset * WeekUtils.DAY_MS);
  }

  static weekNumberForDate(now: Date, startDate: string): number {
    if (startDate.length === 0) {
      return 1;
    }
    const start: Date = WeekUtils.parseStartDate(startDate);
    const monday: Date = WeekUtils.mondayOnOrBefore(start);
    const diffDays: number = Math.floor((now.getTime() - monday.getTime()) / WeekUtils.DAY_MS);
    if (diffDays < 0) {
      return 0;
    }
    return Math.floor(diffDays / 7) + 1;
  }

  static currentWeek(startDate: string, weekCount: number, offset: number): number {
    if (startDate.length === 0) {
      return 1;
    }
    const base: number = WeekUtils.weekNumberForDate(new Date(), startDate);
    const baseSafe: number = Math.max(1, base);
    const target: number = baseSafe + offset;
    return Math.max(1, Math.min(Math.max(1, weekCount), target));
  }

  static weekStart(startDate: string, week: number): Date {
    const start: Date = WeekUtils.parseStartDate(startDate);
    const monday: Date = WeekUtils.mondayOnOrBefore(start);
    return new Date(monday.getTime() + (week - 1) * WeekUtils.WEEK_MS);
  }

  static formatMD(d: Date): string {
    return `${d.getMonth() + 1}/${d.getDate()}`;
  }

  static parseStartDate(startDate: string): Date {
    const parts: string[] = startDate.split('-');
    const year: number = parseInt(parts[0], 10);
    const month: number = parseInt(parts[1], 10);
    const day: number = parseInt(parts[2], 10);
    if (!isFinite(year) || !isFinite(month) || !isFinite(day)) {
      return new Date();
    }
    return new Date(year, month - 1, day);
  }

  static formatDate(d: Date): string {
    const year: number = d.getFullYear();
    const month: number = d.getMonth() + 1;
    const day: number = d.getDate();
    return `${year}-${month < 10 ? '0' : ''}${month}-${day < 10 ? '0' : ''}${day}`;
  }
}
