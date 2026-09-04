import { Course, TimeSlot } from '../model/CourseModel';
import { WeekUtils } from '../model/WeekUtils';
import { ScheduleTimes } from '../model/ScheduleTimes';

class GridBlock {
  course: Course | undefined = undefined;
  slot: TimeSlot | undefined = undefined;
  emptyRun: number = 0;
  endSection: number = 0;
}

class DayColumnData {
  day: number = 0;
  blocks: GridBlock[] = [];
}

class SlotRef {
  course: Course | undefined = undefined;
  slot: TimeSlot | undefined = undefined;
}

@Component
export struct ScheduleGrid {
  @Prop courses: Course[] = [];
  @Prop week: number = 1;
  @Prop weekStartDate: string = '';

  private readonly MAX_SECTIONS: number = 13;
  private readonly CELL_HEIGHT: number = 52;
  private readonly TIME_COL_WIDTH: number = 36;
  private readonly CORNER_RADIUS: number = 6;

  private dayLabels(): string[] {
    return ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  }

  private dayHeaderDates(): string[] {
    const dates: string[] = [];
    if (this.weekStartDate.length === 0) {
      for (let i = 0; i < 7; i++) {
        dates.push('');
      }
      return dates;
    }
    const start: Date = WeekUtils.parseStartDate(this.weekStartDate);
    for (let i = 0; i < 7; i++) {
      const d: Date = new Date(start.getTime() + i * 24 * 60 * 60 * 1000);
      dates.push(WeekUtils.formatMD(d));
    }
    return dates;
  }

  private courseMatchesWeek(course: Course, slot: TimeSlot): boolean {
    return WeekUtils.isWeekInRange(this.week, slot.weekRange) &&
      WeekUtils.matchesRepeatRule(this.week, slot.repeatRule);
  }

  private hasCoursesInWeek(): boolean {
    for (let i = 0; i < this.courses.length; i++) {
      const c: Course = this.courses[i];
      for (let j = 0; j < c.timeSlots.length; j++) {
        const slot: TimeSlot = c.timeSlots[j];
        if (slot.dayOfWeek >= 1 && slot.dayOfWeek <= 7 &&
          slot.sectionStart >= 1 && slot.sectionEnd >= slot.sectionStart &&
          this.courseMatchesWeek(c, slot)) {
          return true;
        }
      }
    }
    return false;
  }

  private buildDayColumn(day: number): DayColumnData {
    const col: DayColumnData = new DayColumnData();
    col.day = day;
    const matched: SlotRef[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      const c: Course = this.courses[i];
      for (let j = 0; j < c.timeSlots.length; j++) {
        const slot: TimeSlot = c.timeSlots[j];
        if (slot.dayOfWeek === day && slot.sectionStart >= 1 &&
          slot.sectionEnd >= slot.sectionStart && this.courseMatchesWeek(c, slot)) {
          const ref: SlotRef = new SlotRef();
          ref.course = c;
          ref.slot = slot;
          matched.push(ref);
        }
      }
    }
    matched.sort((a: SlotRef, b: SlotRef) => {
      const sa: number = a.slot !== undefined ? a.slot.sectionStart : 99;
      const sb: number = b.slot !== undefined ? b.slot.sectionStart : 99;
      return sa - sb;
    });

    let cursor: number = 1;
    let lastBlock: GridBlock | undefined = undefined;
    for (let i = 0; i < matched.length; i++) {
      const ref: SlotRef = matched[i];
      if (ref.slot === undefined || ref.course === undefined) {
        continue;
      }
      if (ref.slot.sectionStart > cursor) {
        const empty: GridBlock = new GridBlock();
        empty.emptyRun = ref.slot.sectionStart - cursor;
        col.blocks.push(empty);
        lastBlock = undefined;
      }
      const mergeable: boolean = lastBlock !== undefined &&
        lastBlock.course !== undefined &&
        lastBlock.slot !== undefined &&
        lastBlock.course.id === ref.course.id &&
        lastBlock.slot.dayOfWeek === ref.slot.dayOfWeek &&
        (lastBlock.slot.sectionEnd === undefined ? false : lastBlock.slot.sectionEnd + 1 === ref.slot.sectionStart);
      if (mergeable && lastBlock !== undefined) {
        lastBlock.endSection = ref.slot.sectionEnd;
        cursor = ref.slot.sectionEnd + 1;
        continue;
      }
      const block: GridBlock = new GridBlock();
      block.course = ref.course;
      block.slot = ref.slot;
      block.endSection = ref.slot.sectionEnd;
      col.blocks.push(block);
      lastBlock = block;
      cursor = ref.slot.sectionEnd + 1;
    }
    if (cursor <= this.MAX_SECTIONS) {
      const empty: GridBlock = new GridBlock();
      empty.emptyRun = this.MAX_SECTIONS - cursor + 1;
      col.blocks.push(empty);
    }
    return col;
  }

  private buildAllColumns(): DayColumnData[] {
    const cols: DayColumnData[] = [];
    for (let day = 1; day <= 7; day++) {
      cols.push(this.buildDayColumn(day));
    }
    return cols;
  }

  private slotCampus(slot: TimeSlot): string {
    if (slot.campus.length > 0) {
      return slot.campus;
    }
    return '长安校区';
  }

  build() {
    Scroll() {
      Column() {
        if (!this.hasCoursesInWeek()) {
          Column() {
            Text(this.weekStartDate.length === 0 ? '本周无课程 · 请确认已设置第一周' : '本周无课程')
              .fontSize(12)
              .fontColor($r('app.color.text_hint'))
              .margin({ top: 16, bottom: 16 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
        }

        Row() {
          Column() {
            Text('节')
              .fontSize(9)
              .fontColor($r('app.color.text_hint'))
              .fontWeight(FontWeight.Bold)
          }
          .width(this.TIME_COL_WIDTH)
          .height(48)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderWidth(0.5)
          .borderColor($r('app.color.schedule_line'))
          .backgroundColor($r('app.color.schedule_empty_bg'))

          ForEach(this.dayLabels(), (label: string, idx: number) => {
            Column() {
              Text(label)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
                .fontWeight(FontWeight.Bold)
              Text(this.dayHeaderDates()[idx])
                .fontSize(8)
                .fontColor($r('app.color.text_hint'))
                .margin({ top: 1 })
            }
            .layoutWeight(1)
            .height(48)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderWidth(0.5)
            .borderColor($r('app.color.schedule_line'))
            .backgroundColor($r('app.color.schedule_empty_bg'))
          }, (label: string, idx: number) => `h_${idx}`)
        }
        .width('100%')

        Row() {
          Column() {
            ForEach(this.sectionLabels(), (item: string, idx: number) => {
              Column() {
                Text(`${idx + 1}`)
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .fontWeight(FontWeight.Bold)
                if (item.length > 0) {
                  Text(item)
                    .fontSize(7)
                    .fontColor($r('app.color.text_hint'))
                    .margin({ top: 1 })
                }
              }
              .width(this.TIME_COL_WIDTH)
              .height(this.CELL_HEIGHT)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderWidth(0.5)
              .borderColor($r('app.color.schedule_line'))
              .backgroundColor($r('app.color.schedule_empty_bg'))
            }, (item: string, idx: number) => `t_${this.week}_${idx}`)
          }
          .width(this.TIME_COL_WIDTH)

          ForEach(this.buildAllColumns(), (col: DayColumnData) => {
            Column() {
              ForEach(col.blocks, (block: GridBlock, bi: number) => {
                if (block.course !== undefined && block.slot !== undefined) {
                  this.CourseBlock(block.course, block.slot, block.endSection)
                } else {
                  ForEach(this.emptyCellIndexes(block.emptyRun), (ei: number) => {
                    Column()
                      .width('100%')
                      .height(this.CELL_HEIGHT)
                      .borderWidth(0.5)
                      .borderColor($r('app.color.schedule_line'))
                      .backgroundColor($r('app.color.schedule_empty_bg'))
                  }, (ei: number) => `e_${this.week}_${col.day}_${bi}_${ei}`)
                }
              }, (block: GridBlock, bi: number) => `b_${this.week}_${col.day}_${bi}`)
            }
            .layoutWeight(1)
          }, (col: DayColumnData) => `d_${this.week}_${col.day}`)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
}
      .width('100%')
      .padding({ bottom: 100 })
    }
    .width('100%')
    .scrollBar(BarState.Off)
  }

  private emptyCellIndexes(run: number): number[] {
    const arr: number[] = [];
    for (let i = 0; i < run; i++) {
      arr.push(i);
    }
    return arr;
  }

  private sectionLabels(): string[] {
    const labels: string[] = [];
    const now: Date = new Date();
    for (let s = 1; s <= this.MAX_SECTIONS; s++) {
      labels.push(ScheduleTimes.startTimeFor('长安校区', now, s));
    }
    return labels;
  }

  @Builder
  CourseBlock(course: Course, slot: TimeSlot, blockEndSection: number) {
    Column() {
      Text(course.name)
        .fontSize(9)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Start)

      if (slot.sectionStart > 0) {
        Text(this.courseBlockTimeText(slot, blockEndSection))
          .fontSize(7)
          .fontColor('#FFFFFFCC')
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: 2 })
      }

      if (slot.location.length > 0) {
        Text(slot.location)
          .fontSize(7)
          .fontColor('#FFFFFFCC')
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .height(this.CELL_HEIGHT * (this.blockSpan(slot, blockEndSection)))
    .padding(4)
    .borderRadius(this.CORNER_RADIUS)
    .backgroundColor(course.getColor())
    .borderWidth(0.5)
    .borderColor(course.getColor())
  }

  private blockSpan(slot: TimeSlot, blockEndSection: number): number {
    let end: number = blockEndSection;
    if (end < slot.sectionStart) {
      end = slot.sectionEnd;
    }
    return end - slot.sectionStart + 1;
  }

  private courseBlockTimeText(slot: TimeSlot, blockEndSection: number): string {
    let end: number = blockEndSection;
    if (end < slot.sectionStart) {
      end = slot.sectionEnd;
    }
    const time: string = ScheduleTimes.timeSpanFor(this.slotCampus(slot), new Date(), slot.sectionStart, end);
    if (time.length > 0) {
      return `${slot.sectionStart}${end > slot.sectionStart ? '-' + end : ''}节 ${time}`;
    }
    return `${slot.sectionStart}${end > slot.sectionStart ? '-' + end : ''}节`;
  }
}