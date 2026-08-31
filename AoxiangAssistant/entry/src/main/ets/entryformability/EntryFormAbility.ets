import { FormExtensionAbility, formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WidgetDataBuilder } from '../model/WidgetDataBuilder';
import { WidgetSnapshotStore } from '../model/WidgetSnapshotStore';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const parameters: Record<string, Object> = want.parameters as Record<string, Object>;
    if (parameters === undefined || parameters === null) {
      return formBindingData.createFormBindingData({});
    }
    const formName: string = (parameters[formInfo.FormParam.NAME_KEY] as string) ?? 'daily_card';
    const formId: string = (parameters[formInfo.FormParam.IDENTITY_KEY] as string) ?? '';
    console.info(`EntryFormAbility.onAddForm formId=${formId} name=${formName}`);
    const data: formBindingData.FormBindingData =
      this.initialBindingData(formName);
    if (formId.length > 0) {
      WidgetSnapshotStore.registerForm(this.context, formId, formName)
        .catch((e: BusinessError) => {
          console.error(`registerForm error: ${e.code} ${e.message}`);
        });
    }
    return data;
  }

  onUpdateForm(formId: string): void {
    console.info(`EntryFormAbility.onUpdateForm formId=${formId}`);
    WidgetSnapshotStore.findFormName(this.context, formId).then((formName: string) => {
      const name: string = formName.length > 0 ? formName : 'daily_card';
      WidgetSnapshotStore.loadSnapshot(this.context, name).then((json: string) => {
        const data: string = json.length > 0 ? json : WidgetDataBuilder.defaultJson(name);
        formProvider.updateForm(formId, formBindingData.createFormBindingData({ cardData: data }))
          .then(() => {
            console.info(`updateForm ok formId=${formId} name=${name}`);
          })
          .catch((e: BusinessError) => {
            console.error(`updateForm error: ${e.code} ${e.message}`);
          });
      });
    });
  }

  onRemoveForm(formId: string): void {
    console.info(`EntryFormAbility.onRemoveForm formId=${formId}`);
    WidgetSnapshotStore.unregisterForm(this.context, formId)
      .catch((e: BusinessError) => {
        console.error(`unregisterForm error: ${e.code} ${e.message}`);
      });
  }

  onFormEvent(formId: string, message: string): void {
    console.info(`EntryFormAbility.onFormEvent formId=${formId} message=${message}`);
  }

  private initialBindingData(formName: string): formBindingData.FormBindingData {
    const data: string = WidgetDataBuilder.defaultJson(formName);
    return formBindingData.createFormBindingData({ cardData: data });
  }
}