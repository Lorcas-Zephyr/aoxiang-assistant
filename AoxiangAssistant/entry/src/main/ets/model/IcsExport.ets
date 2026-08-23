import { Course, TimeSlot, Semester } from './CourseModel';
import { WeekUtils } from './WeekUtils';
import { ScheduleTimes } from './ScheduleTimes';

export class IcsExport {
  private static readonly DAYS: string[] = ['', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
  private static readonly TZID: string = 'Asia/Shanghai';
  private static readonly MS_PER_DAY: number = 24 * 60 * 60 * 1000;

  static generate(courses: Course[], semester: Semester, now: Date): string {
    let ics: string = 'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n' +
      'PRODID:-//AoxiangAssistant//NWPU Schedule//CN\r\nCALSCALE:GREGORIAN\r\n';

    const filtered: Course[] = [];
    for (let i = 0; i < courses.length; i++) {
      if (courses[i].dataSemester === semester.dataSemester) {
        filtered.push(courses[i]);
      }
    }

    for (let i = 0; i < filtered.length; i++) {
      const course: Course = filtered[i];
      for (let j = 0; j < course.timeSlots.length; j++) {
        ics += IcsExport.buildVevent(course, course.timeSlots[j], semester, now);
      }
    }

    ics += 'END:VCALENDAR\r\n';
    return ics;
  }

  private static buildVevent(course: Course, slot: TimeSlot, semester: Semester, now: Date): string {
    if (semester.startDate.length === 0) {
      return '';
    }
    const weeks: number[] = WeekUtils.parseWeeks(slot.weekRange);
    if (weeks.length === 0) {
      return '';
    }
    const firstWeek: number = weeks[0];
    const lastWeek: number = weeks[weeks.length - 1];
    const dayOfWeek: number = slot.dayOfWeek;
    if (dayOfWeek < 1 || dayOfWeek > 7) {
      return '';
    }

    const weekStart: Date = WeekUtils.weekStart(semester.startDate, firstWeek);
    const eventDate: Date = new Date(weekStart.getTime() + (dayOfWeek - 1) * IcsExport.MS_PER_DAY);

    const campus: string = slot.campus.length > 0 ? slot.campus : '长安校区';
    const timeSpan: string = ScheduleTimes.timeSpanFor(campus, now, slot.sectionStart, slot.sectionEnd);
    if (timeSpan.length === 0) {
      return '';
    }
    const timeParts: string[] = timeSpan.split('-');
    const startTime: string = timeParts[0];
    const endTime: string = timeParts[1];

    const dtStart: string = IcsExport.formatIcsDate(eventDate, startTime);
    const dtEnd: string = IcsExport.formatIcsDate(eventDate, endTime);

    const lastWeekStart: Date = WeekUtils.weekStart(semester.startDate, lastWeek);
    const lastDate: Date = new Date(lastWeekStart.getTime() + (dayOfWeek - 1) * IcsExport.MS_PER_DAY);
    const until: string = IcsExport.formatIcsDate(lastDate, '23:59:59');

    const byDay: string = IcsExport.DAYS[dayOfWeek];
    let rrule: string;
    if (slot.repeatRule === '仅单周') {
      rrule = `RRULE:FREQ=WEEKLY;BYDAY=${byDay};INTERVAL=2;WKST=MO;UNTIL=${until}`;
    } else if (slot.repeatRule === '仅双周') {
      const firstDate: Date = new Date(eventDate.getTime() + 7 * IcsExport.MS_PER_DAY);
      const dtStartAlt: string = IcsExport.formatIcsDate(firstDate, startTime);
      rrule = `RRULE:FREQ=WEEKLY;BYDAY=${byDay};INTERVAL=2;WKST=MO;UNTIL=${until}`;
      const desc: string = IcsExport.buildDescription(course, slot);
      const loc: string = slot.location.length > 0 ? slot.location.replace(/,/g, '\\,') : '';
      let vevent: string = `BEGIN:VEVENT\r\nDTSTART;TZID=${IcsExport.TZID}:${dtStartAlt}\r\nDTEND;TZID=${IcsExport.TZID}:${dtEnd}\r\n`;
      vevent += `${rrule}\r\nSUMMARY:${IcsExport.escapeText(course.name)}\r\n`;
      if (desc.length > 0) {
        vevent += `DESCRIPTION:${IcsExport.escapeText(desc)}\r\n`;
      }
      if (loc.length > 0) {
        vevent += `LOCATION:${loc}\r\n`;
      }
      vevent += 'END:VEVENT\r\n';
      return vevent;
    } else {
      rrule = `RRULE:FREQ=WEEKLY;BYDAY=${byDay};UNTIL=${until}`;
    }

    const desc: string = IcsExport.buildDescription(course, slot);
    const loc: string = slot.location.length > 0 ? slot.location.replace(/,/g, '\\,') : '';

    let vevent: string = `BEGIN:VEVENT\r\nDTSTART;TZID=${IcsExport.TZID}:${dtStart}\r\nDTEND;TZID=${IcsExport.TZID}:${dtEnd}\r\n`;
    vevent += `${rrule}\r\nSUMMARY:${IcsExport.escapeText(course.name)}\r\n`;
    if (desc.length > 0) {
      vevent += `DESCRIPTION:${IcsExport.escapeText(desc)}\r\n`;
    }
    if (loc.length > 0) {
      vevent += `LOCATION:${loc}\r\n`;
    }
    vevent += 'END:VEVENT\r\n';
    return vevent;
  }

  private static buildDescription(course: Course, slot: TimeSlot): string {
    const parts: string[] = [];
    if (course.teacher.length > 0) {
      parts.push(`教师：${course.teacher}`);
    }
    if (slot.location.length > 0) {
      parts.push(`地点：${slot.location}`);
    }
    if (slot.campus.length > 0) {
      parts.push(`校区：${slot.campus}`);
    }
    if (slot.weekRange.length > 0) {
      parts.push(`周次：${slot.weekRange}周`);
    }
    if (slot.repeatRule.length > 0) {
      parts.push(`规则：${slot.repeatRule}`);
    }
    if (course.code.length > 0) {
      parts.push(`课程代码：${course.code}`);
    }
    return parts.join('\\n');
  }

  private static formatIcsDate(date: Date, time: string): string {
    const y: number = date.getFullYear();
    const m: number = date.getMonth() + 1;
    const d: number = date.getDate();
    const timeParts: string[] = time.split(':');
    const h: string = timeParts[0];
    const min: string = timeParts[1];
    const sec: string = timeParts.length > 2 ? timeParts[2] : '00';
    return `${y}${IcsExport.pad(m)}${IcsExport.pad(d)}T${IcsExport.pad(parseInt(h, 10))}${IcsExport.pad(parseInt(min, 10))}${sec}`;
  }

  private static pad(n: number): string {
    return n < 10 ? '0' + n : '' + n;
  }

  private static escapeText(text: string): string {
    return text.replace(/,/g, '\\,').replace(/;/g, '\\;').replace(/\n/g, '\\n');
  }
}