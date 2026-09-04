export class Course {
  name: string = '';
  code: string = '';
  teacher: string = '';
  scheduleText: string = '';
  location: string = '';
  dataSemester: string = '';
  dayOfWeek: number = 0;
  sectionStart: number = 0;
  sectionEnd: number = 0;
  colorIndex: number = 0;

  displayDay(): string {
    const labels: string[] = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return this.dayOfWeek >= 1 && this.dayOfWeek <= 7 ? labels[this.dayOfWeek] : '';
  }

  displaySection(): string {
    if (this.sectionStart > 0 && this.sectionEnd > 0) {
      return `第${this.sectionStart}-${this.sectionEnd}节`;
    }
    return this.scheduleText;
  }

  getColor(): string {
    return CoursePresetColors.COLORS[this.colorIndex % CoursePresetColors.COLORS.length];
  }

  sectionSpan(): number {
    if (this.sectionStart > 0 && this.sectionEnd >= this.sectionStart) {
      return this.sectionEnd - this.sectionStart + 1;
    }
    return 1;
  }

  static fromJsObject(obj: Record<string, Object>): Course {
    const c: Course = new Course();
    c.name = (obj['name'] ?? '') as string;
    c.code = (obj['code'] ?? '') as string;
    c.teacher = (obj['teacher'] ?? '') as string;
    c.scheduleText = (obj['scheduleText'] ?? '') as string;
    c.location = (obj['location'] ?? '') as string;
    c.dataSemester = (obj['dataSemester'] ?? '') as string;
    const ci: Object | undefined = obj['colorIndex'];
    c.colorIndex = ci !== undefined && ci !== null ? (ci as number) : 0;
    c.parseScheduleText();
    return c;
  }

  parseScheduleText(): void {
    if (this.scheduleText.length === 0) {
      return;
    }
    const dayMap: Record<string, number> = {
      '周一': 1, '周二': 2, '周三': 3, '周四': 4,
      '周五': 5, '周六': 6, '周日': 7, '周天': 7,
      '星期一': 1, '星期二': 2, '星期三': 3, '星期四': 4,
      '星期五': 5, '星期六': 6, '星期日': 7,
    };
    for (const key of Object.keys(dayMap)) {
      if (this.scheduleText.includes(key)) {
        this.dayOfWeek = dayMap[key];
        break;
      }
    }
    const sectionMatch: RegExpMatchArray | null = this.scheduleText.match(/第\s*(\d+)\s*[-–—]\s*(\d+)\s*节/);
    if (sectionMatch !== null && sectionMatch.length >= 3) {
      this.sectionStart = parseInt(sectionMatch[1], 10);
      this.sectionEnd = parseInt(sectionMatch[2], 10);
    }
  }

  toRecord(): Record<string, Object> {
    const obj: Record<string, Object> = {
      'name': this.name,
      'code': this.code,
      'teacher': this.teacher,
      'scheduleText': this.scheduleText,
      'location': this.location,
      'dataSemester': this.dataSemester,
      'colorIndex': this.colorIndex,
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

  static fromJsObject(obj: Record<string, Object>): Semester {
    const s: Semester = new Semester();
    s.name = (obj['name'] ?? '') as string;
    s.dataSemester = (obj['dataSemester'] ?? '') as string;
    return s;
  }

  toRecord(): Record<string, Object> {
    return { 'name': this.name, 'dataSemester': this.dataSemester };
  }
}
