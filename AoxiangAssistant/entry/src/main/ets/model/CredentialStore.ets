import huks from '@ohos.security.huks';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';

const KEY_ALIAS: string = 'campus_login_credentials';
const PREF_NAME: string = 'campus_private';
const CREDENTIAL_KEY: string = 'login_credentials';

function genEmptyOptions(): huks.HuksOptions {
  const options: huks.HuksOptions = {
    properties: [],
    inData: new Uint8Array(0)
  };
  return options;
}

function aes256GcmKeyOptions(): Array<huks.HuksParam> {
  const props: Array<huks.HuksParam> = [
    { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
    { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
    {
      tag: huks.HuksTag.HUKS_TAG_PURPOSE,
      value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
    },
    { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
    { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
  ];
  return props;
}

export class CredentialStore {
  private pref: preferences.Preferences | undefined = undefined;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.pref = await preferences.getPreferences(context, PREF_NAME);
  }

  async saveCredentials(username: string, password: string): Promise<boolean> {
    if (this.pref === undefined) {
      return false;
    }
    const plainText: string = username + '\n' + password;
    const encrypted: string = await this.encrypt(plainText);
    if (encrypted.length === 0) {
      return false;
    }
    this.pref.putSync(CREDENTIAL_KEY, encrypted);
    await this.pref.flush();
    return true;
  }

  async readCredentials(): Promise<string[]> {
    if (this.pref === undefined) {
      return ['', ''];
    }
    const value: string = this.pref.getSync(CREDENTIAL_KEY, '') as string;
    if (value.length === 0) {
      return ['', ''];
    }
    const colonIdx: number = value.indexOf(':');
    if (colonIdx < 0) {
      return ['', ''];
    }
    const nonceB64: string = value.substring(0, colonIdx);
    const cipherB64: string = value.substring(colonIdx + 1);
    const decrypted: string = await this.decrypt(nonceB64, cipherB64);
    if (decrypted.length === 0) {
      return ['', ''];
    }
    const newlineIdx: number = decrypted.indexOf('\n');
    if (newlineIdx < 0) {
      return [decrypted, ''];
    }
    const user: string = decrypted.substring(0, newlineIdx);
    const pass: string = decrypted.substring(newlineIdx + 1);
    return [user, pass];
  }

  async clearCredentials(): Promise<void> {
    if (this.pref === undefined) {
      return;
    }
    this.pref.deleteSync(CREDENTIAL_KEY);
    await this.pref.flush();
    try {
      huks.deleteKeyItem(KEY_ALIAS, genEmptyOptions());
    } catch (ignored) {
    }
  }

  hasCredentials(): boolean {
    if (this.pref === undefined) {
      return false;
    }
    const value: string = this.pref.getSync(CREDENTIAL_KEY, '') as string;
    return value.length > 0;
  }

  private async ensureKey(): Promise<void> {
    const isExist: boolean = await this.isKeyExist();
    if (!isExist) {
      const genOptions: huks.HuksOptions = {
        properties: aes256GcmKeyOptions(),
        inData: new Uint8Array(0)
      };
      await huks.generateKeyItem(KEY_ALIAS, genOptions);
    }
  }

  private async isKeyExist(): Promise<boolean> {
    try {
      const huksOptions: huks.HuksOptions = {
        properties: aes256GcmKeyOptions(),
        inData: new Uint8Array(0)
      };
      const result: boolean = await huks.isKeyItemExist(KEY_ALIAS, huksOptions);
      return result;
    } catch (e) {
      return false;
    }
  }

  private async encrypt(plainText: string): Promise<string> {
    try {
      await this.ensureKey();
      const encoder: util.TextEncoder = new util.TextEncoder();
      const inData: Uint8Array = encoder.encodeInto(plainText);
      const encryptProps: Array<huks.HuksParam> = [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      ];
      const encryptOptions: huks.HuksOptions = {
        properties: encryptProps,
        inData: inData
      };
      const initResult: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, encryptOptions);
      const handle: number = initResult.handle;
      const finishResult: huks.HuksReturnResult = await huks.finishSession(handle, encryptOptions);
      const outData: Uint8Array = finishResult.outData as Uint8Array;
      const nonceLen: number = 12;
      const nonce: Uint8Array = outData.slice(0, nonceLen);
      const ciphertext: Uint8Array = outData.slice(nonceLen);
      const base64Helper: util.Base64Helper = new util.Base64Helper();
      const nonceB64: string = base64Helper.encodeToStringSync(nonce);
      const cipherB64: string = base64Helper.encodeToStringSync(ciphertext);
      return nonceB64 + ':' + cipherB64;
    } catch (e) {
      const error = e as BusinessError;
      console.error(`encrypt failed: ${error.code} ${error.message}`);
      return '';
    }
  }

  private async decrypt(nonceB64: string, cipherB64: string): Promise<string> {
    try {
      await this.ensureKey();
      const base64Helper: util.Base64Helper = new util.Base64Helper();
      const nonce: Uint8Array = base64Helper.decodeSync(nonceB64);
      const ciphertext: Uint8Array = base64Helper.decodeSync(cipherB64);
      const combined: Uint8Array = new Uint8Array(nonce.length + ciphertext.length);
      combined.set(nonce, 0);
      combined.set(ciphertext, nonce.length);
      const decryptProps: Array<huks.HuksParam> = [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
        { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
        { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: new Uint8Array(0) },
      ];
      const decryptOptions: huks.HuksOptions = {
        properties: decryptProps,
        inData: combined
      };
      const initResult: huks.HuksSessionHandle = await huks.initSession(KEY_ALIAS, decryptOptions);
      const handle: number = initResult.handle;
      const finishResult: huks.HuksReturnResult = await huks.finishSession(handle, decryptOptions);
      const outData: Uint8Array = finishResult.outData as Uint8Array;
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(outData);
    } catch (e) {
      const error = e as BusinessError;
      console.error(`decrypt failed: ${error.code} ${error.message}`);
      return '';
    }
  }
}
