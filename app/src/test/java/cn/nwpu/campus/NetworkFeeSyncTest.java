package cn.nwpu.campus;

import org.junit.Test;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

public class NetworkFeeSyncTest {
    @Test public void readsAccountTotalBalanceFromHtmlAndVisibleText() {
        assertEquals("0", NetworkFeeSync.parseBalance(
                "<tr><td>￥账户总余额</td><td><span>0</span></td></tr>"));
        assertEquals("12.30", NetworkFeeSync.parseBalance("账户总余额\n¥ 12.30\n缴费"));
        assertEquals("-3.50", NetworkFeeSync.parseBalance("账户余额：-3.50 元"));
        assertEquals("8.25", NetworkFeeSync.parseBalance(
                "<div>可用余额</div><b>&nbsp;8.25</b>"));
    }

    @Test public void doesNotTreatSourceCodeOrUnrelatedNumbersAsBalance() {
        assertNull(NetworkFeeSync.parseBalance("<script>var label='账户余额';var value=2025;</script>登录"));
        assertNull(NetworkFeeSync.parseBalance("账户余额 登录后查看 用户名2025300000"));
        assertNull(NetworkFeeSync.parseBalance("用户名 2025300000 套餐 30GB"));
    }

    @Test public void savesOnlyNetworkSessionCookies() {
        assertEquals("PHPSESSID_8800=session; _csrf-8800=csrf",
                NetworkFeeSession.sessionCookie("portal_token=private; PHPSESSID_8800=session; "
                        + "_csrf-8800=csrf; Domain=.nwpu.edu.cn; tracking=ignored"));
        assertEquals("", NetworkFeeSession.sessionCookie("_csrf-8800=csrf; portal_token=private"));
        assertEquals("", NetworkFeeSession.sessionCookie("PHPSESSID_8800=; _csrf-8800=csrf"));
    }

    @Test public void rejectsInjectedCookieHeaders() {
        assertEquals("", NetworkFeeSession.sessionCookie("PHPSESSID_8800=session\r\nHost: other.test"));
        assertEquals("", NetworkFeeSession.sessionCookie(null));
    }
}
