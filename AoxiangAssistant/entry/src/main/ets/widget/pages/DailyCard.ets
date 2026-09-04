class CardCourse {
  time: string = '';
  section: string = '';
  name: string = '';
  loc: string = '';
  teacher: string = '';
  color: string = '#1E88E5';
}

class DailyData {
  title: string = '今日课表';
  date: string = '';
  hint: string = '';
  empty: boolean = true;
  courses: CardCourse[] = [];
}

const dailyStorage = new LocalStorage();

@Entry(dailyStorage)
@Component
struct DailyCard {
  @LocalStorageProp('cardData') @Watch('onDataChanged') cardData: string = '';
  @State title: string = '今日课表';
  @State date: string = '';
  @State hint: string = '';
  @State empty: boolean = true;
  @State courses: CardCourse[] = [];

  aboutToAppear(): void {
    this.parseData();
  }

  onDataChanged(propName: string): void {
    this.parseData();
  }

  private parseData(): void {
    const data: DailyData = new DailyData();
    if (this.cardData.length > 0) {
      try {
        const obj: Record<string, Object> = JSON.parse(this.cardData) as Record<string, Object>;
        data.title = (obj['title'] ?? '今日课表') as string;
        data.date = (obj['date'] ?? '') as string;
        data.hint = (obj['hint'] ?? '') as string;
        data.empty = (obj['empty'] ?? true) === true;
        const rawCourses: Object[] = obj['courses'] as Object[];
        if (rawCourses !== undefined && rawCourses !== null) {
          for (let i = 0; i < rawCourses.length; i++) {
            const c: Record<string, Object> = rawCourses[i] as Record<string, Object>;
            const item: CardCourse = new CardCourse();
            item.time = (c['time'] ?? '') as string;
            item.section = (c['section'] ?? '') as string;
            item.name = (c['name'] ?? '') as string;
            item.loc = (c['loc'] ?? '') as string;
            item.teacher = (c['teacher'] ?? '') as string;
            item.color = (c['color'] ?? '#1E88E5') as string;
            data.courses.push(item);
          }
        }
      } catch (e) {
        console.error(`DailyCard parse error: ${e}`);
      }
    }
    this.title = data.title;
    this.date = data.date;
    this.hint = data.hint;
    this.empty = data.empty;
    this.courses = data.courses;
  }

  private hasCourses(): boolean {
    return this.courses.length > 0;
  }

  @Builder
  CourseItem(item: CardCourse) {
    Row() {
      Column() {
        Text(item.section)
          .fontSize(10)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
        if (item.time.length > 0) {
          Text(item.time)
            .fontSize(9)
            .fontColor(Color.White)
            .margin({ top: 1 })
        }
      }
      .alignItems(HorizontalAlign.Center)
      .width('28%')

      Column() {
        Text(item.name)
          .fontSize(11)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (item.loc.length > 0) {
          Text(item.loc)
            .fontSize(9)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
        if (item.teacher.length > 0) {
          Text(item.teacher)
            .fontSize(9)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 6 })
    }
    .width('100%')
    .padding(6)
    .borderRadius(6)
    .backgroundColor(item.color)
    .margin({ bottom: 4 })
  }

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(12)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
        if (this.date.length > 0) {
          Text(this.date)
            .fontSize(10)
            .fontColor('#FFFFFFCC')
            .margin({ left: 6 })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 4 })

      if (this.courses.length > 0) {
        ForEach(this.courses, (item: CardCourse, idx: number) => {
          this.CourseItem(item)
        }, (item: CardCourse, idx: number) => `${item.section}_${item.name}_${idx}`)
      } else {
        Column() {
          Text(this.hint.length > 0 ? this.hint : '今日无课')
            .fontSize(11)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor('#1F1F1F')
    .borderRadius(12)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility'
      });
    })
  }
}
