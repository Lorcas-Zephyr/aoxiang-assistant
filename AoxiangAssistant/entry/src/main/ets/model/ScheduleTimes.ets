export class ScheduleTimes {
  private static readonly CHANG_AN: string[] = [
    '08:30-09:15', '09:25-10:10', '10:30-11:15', '11:25-12:10', '12:20-13:05',
    '13:05-13:50', '14:00-14:45', '14:55-15:40', '16:00-16:45', '16:55-17:40',
    '19:00-19:45', '19:55-20:40', '20:40-21:25',
  ];
  private static readonly FRIENDLY_SUMMER: string[] = [
    '08:00-08:50', '09:00-09:50', '10:10-11:00', '11:10-12:00', '12:20-13:05',
    '13:05-13:50', '14:30-15:20', '15:30-16:20', '16:40-17:30', '17:40-18:30',
    '19:30-20:20', '20:30-21:20', '',
  ];
  private static readonly FRIENDLY_WINTER: string[] = [
    '08:00-08:50', '09:00-09:50', '10:10-11:00', '11:10-12:00', '12:20-13:05',
    '13:05-13:50', '14:00-14:50', '15:00-15:50', '16:10-17:00', '17:10-18:00',
    '19:00-19:50', '20:00-20:50', '',
  ];

  static isSummerSeason(date: Date): boolean {
    const month: number = date.getMonth() + 1;
    return month >= 5 && month <= 9;
  }

  private static tableFor(campus: string, date: Date): string[] {
    if (campus.includes('长安')) {
      return ScheduleTimes.CHANG_AN;
    }
    if (campus.includes('友谊')) {
      return ScheduleTimes.isSummerSeason(date) ? ScheduleTimes.FRIENDLY_SUMMER : ScheduleTimes.FRIENDLY_WINTER;
    }
    if (campus.includes('太仓')) {
      return ScheduleTimes.CHANG_AN;
    }
    return ScheduleTimes.CHANG_AN;
  }

  static timeFor(campus: string, date: Date, section: number): string {
    if (section < 1 || section > 13) {
      return '';
    }
    return ScheduleTimes.tableFor(campus, date)[section - 1];
  }

  static startTimeFor(campus: string, date: Date, section: number): string {
    const t: string = ScheduleTimes.timeFor(campus, date, section);
    if (t.length === 0) {
      return '';
    }
    return t.split('-')[0];
  }

  static timeSpanFor(campus: string, date: Date, sectionStart: number, sectionEnd: number): string {
    const start: string = ScheduleTimes.timeFor(campus, date, sectionStart);
    const end: string = ScheduleTimes.timeFor(campus, date, sectionEnd);
    if (start.length === 0 || end.length === 0) {
      return '';
    }
    return `${start.split('-')[0]}-${end.split('-')[1]}`;
  }
}