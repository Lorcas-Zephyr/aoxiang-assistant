import { Course } from '../model/CourseModel';

class GridCell {
  day: number = 0;
  section: number = 0;
  course: Course | undefined = undefined;
  covered: boolean = false;
}

class GridRow {
  section: number = 0;
  cells: GridCell[] = [];
}

@Component
export struct ScheduleGrid {
  @Prop courses: Course[] = [];

  private readonly MAX_SECTIONS: number = 13;
  private readonly CELL_HEIGHT: number = 52;
  private readonly TIME_COL_WIDTH: number = 36;
  private readonly CORNER_RADIUS: number = 6;

  private dayLabels(): string[] {
    return ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  }

  private buildGridData(): GridRow[] {
    const courseMap: Record<string, Course> = {};
    const coveredSet: Record<string, boolean> = {};
    for (let i = 0; i < this.courses.length; i++) {
      const c: Course = this.courses[i];
      if (c.dayOfWeek >= 1 && c.dayOfWeek <= 7 && c.sectionStart >= 1 && c.sectionEnd >= c.sectionStart) {
        const key: string = `${c.dayOfWeek}_${c.sectionStart}`;
        courseMap[key] = c;
        for (let s = c.sectionStart; s <= c.sectionEnd; s++) {
          const ck: string = `${c.dayOfWeek}_${s}`;
          coveredSet[ck] = true;
        }
      }
    }

    const rows: GridRow[] = [];
    for (let section = 1; section <= this.MAX_SECTIONS; section++) {
      const row: GridRow = new GridRow();
      row.section = section;
      const cells: GridCell[] = [];
      for (let day = 1; day <= 7; day++) {
        const cell: GridCell = new GridCell();
        cell.day = day;
        cell.section = section;
        const startKey: string = `${day}_${section}`;
        if (courseMap[startKey] !== undefined) {
          cell.course = courseMap[startKey];
        } else {
          cell.covered = coveredSet[startKey] !== undefined;
        }
        cells.push(cell);
      }
      row.cells = cells;
      rows.push(row);
    }
    return rows;
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          Column() {
            Text('节')
              .fontSize(9)
              .fontColor($r('app.color.text_hint'))
              .fontWeight(FontWeight.Bold)
          }
          .width(this.TIME_COL_WIDTH)
          .height(36)
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
            }
            .layoutWeight(1)
            .height(36)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderWidth(0.5)
            .borderColor($r('app.color.schedule_line'))
            .backgroundColor($r('app.color.schedule_empty_bg'))
          }, (label: string, idx: number) => `h_${idx}`)
        }
        .width('100%')

        ForEach(this.buildGridData(), (row: GridRow) => {
          Row() {
            Column() {
              Text(`${row.section}`)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
                .fontWeight(FontWeight.Bold)
            }
            .width(this.TIME_COL_WIDTH)
            .height(this.CELL_HEIGHT)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderWidth(0.5)
            .borderColor($r('app.color.schedule_line'))
            .backgroundColor($r('app.color.schedule_empty_bg'))

            ForEach(row.cells, (cell: GridCell) => {
              if (cell.course !== undefined) {
                Stack() {
                  Column() {
                    Text(cell.course.name)
                      .fontSize(9)
                      .fontColor(Color.White)
                      .fontWeight(FontWeight.Bold)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    if (cell.course.location.length > 0) {
                      Text(cell.course.location)
                        .fontSize(7)
                        .fontColor('#FFFFFFCC')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .margin({ top: 2 })
                    }
                  }
                  .width('100%')
                  .height('100%')
                  .padding(3)
                }
                .layoutWeight(1)
                .height(this.CELL_HEIGHT * cell.course.sectionSpan())
                .borderRadius(this.CORNER_RADIUS)
                .backgroundColor(cell.course.getColor())
                .borderWidth(0.5)
                .borderColor(cell.course.getColor())
              } else {
                Column()
                  .layoutWeight(1)
                  .height(this.CELL_HEIGHT)
                  .borderWidth(0.5)
                  .borderColor($r('app.color.schedule_line'))
                  .backgroundColor($r('app.color.schedule_empty_bg'))
              }
            }, (cell: GridCell) => `${cell.day}_${cell.section}`)
          }
          .width('100%')
        }, (row: GridRow) => `r_${row.section}`)
      }
      .width('100%')
    }
    .width('100%')
    .scrollBar(BarState.Off)
  }
}
