const elecStorage = new LocalStorage();

@Entry(elecStorage)
@Component
struct ElectricityCard {
  @LocalStorageProp('cardData') @Watch('onDataChanged') cardData: string = '';
  @State value: string = '--';
  @State unit: string = '元';
  @State empty: boolean = true;
  @State hint: string = '打开应用查询电费';
  @State updated: string = '';

  aboutToAppear(): void {
    this.parseData();
  }

  onDataChanged(propName: string): void {
    this.parseData();
  }

  private parseData(): void {
    if (this.cardData.length > 0) {
      try {
        const obj: Record<string, Object> = JSON.parse(this.cardData) as Record<string, Object>;
        this.value = (obj['value'] ?? '--') as string;
        this.unit = (obj['unit'] ?? '元') as string;
        this.empty = (obj['empty'] ?? true) === true;
        this.hint = (obj['hint'] ?? '打开应用查询电费') as string;
        this.updated = (obj['updated'] ?? '') as string;
      } catch (e) {
        console.error(`ElectricityCard parse error: ${e}`);
      }
    }
  }

  build() {
    Column() {
      Text('电费')
        .fontSize(12)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .textAlign(TextAlign.Start)

      if (this.empty) {
        Column() {
          Text(this.hint)
            .fontSize(10)
            .fontColor($r('app.color.text_hint'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Row() {
          Text(this.value)
            .fontSize(30)
            .fontColor($r('app.color.balance_positive'))
            .fontWeight(FontWeight.Bold)
          Text(this.unit)
            .fontSize(12)
            .fontColor($r('app.color.text_hint'))
            .margin({ left: 4 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .layoutWeight(1)

        if (this.updated.length > 0) {
          Text(`更新于 ${this.updated}`)
            .fontSize(9)
            .fontColor($r('app.color.text_hint'))
            .width('100%')
            .textAlign(TextAlign.End)
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility'
      });
    })
  }
}