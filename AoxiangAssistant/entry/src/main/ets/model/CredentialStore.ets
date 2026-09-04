import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

const PREF_NAME: string = 'campus_private';
const CREDENTIAL_KEY: string = 'login_credentials';
const VERIFIED_KEY: string = 'credentials_verified';

export class CredentialStore {
  private pref: preferences.Preferences | undefined = undefined;
  private base64Helper: util.Base64Helper = new util.Base64Helper();

  async init(context: common.UIAbilityContext): Promise<void> {
    this.pref = await preferences.getPreferences(context, PREF_NAME);
  }

  async saveCredentials(username: string, password: string): Promise<boolean> {
    if (this.pref === undefined) {
      return false;
    }
    const plainText: string = username + '\n' + password;
    const encoder: util.TextEncoder = new util.TextEncoder();
    const encoded: Uint8Array = encoder.encodeInto(plainText);
    const b64: string = this.base64Helper.encodeToStringSync(encoded);
    this.pref.putSync(CREDENTIAL_KEY, b64);
    this.pref.putSync(VERIFIED_KEY, false);
    await this.pref.flush();
    return true;
  }

  async markCredentialsVerified(): Promise<void> {
    if (this.pref === undefined) {
      return;
    }
    this.pref.putSync(VERIFIED_KEY, true);
    await this.pref.flush();
  }

  isCredentialsVerified(): boolean {
    if (this.pref === undefined) {
      return false;
    }
    return this.pref.getSync(VERIFIED_KEY, false) as boolean;
  }

  async readCredentials(): Promise<string[]> {
    if (this.pref === undefined) {
      return ['', ''];
    }
    const value: string = this.pref.getSync(CREDENTIAL_KEY, '') as string;
    if (value.length === 0) {
      return ['', ''];
    }
    const decoded: Uint8Array = this.base64Helper.decodeSync(value);
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    const plainText: string = decoder.decodeToString(decoded);
    const newlineIdx: number = plainText.indexOf('\n');
    if (newlineIdx < 0) {
      return [plainText, ''];
    }
    const user: string = plainText.substring(0, newlineIdx);
    const pass: string = plainText.substring(newlineIdx + 1);
    return [user, pass];
  }

  async clearCredentials(): Promise<void> {
    if (this.pref === undefined) {
      return;
    }
    this.pref.deleteSync(CREDENTIAL_KEY);
    this.pref.deleteSync(VERIFIED_KEY);
    await this.pref.flush();
  }

  hasCredentials(): boolean {
    if (this.pref === undefined) {
      return false;
    }
    const value: string = this.pref.getSync(CREDENTIAL_KEY, '') as string;
    return value.length > 0;
  }
}
