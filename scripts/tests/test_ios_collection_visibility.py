import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
OFFLINE_VIEWS = (
    REPO_ROOT
    / "ios"
    / "AoxiangApp"
    / "Sources"
    / "AoxiangApp"
    / "OfflineViews.swift"
)
AUTHENTICATION_VIEW = (
    REPO_ROOT
    / "ios"
    / "AoxiangApp"
    / "Sources"
    / "AoxiangApp"
    / "VisibleAuthenticationWebView.swift"
)


class IOSCollectionVisibilityTest(unittest.TestCase):
    def test_authentication_surface_stays_visible_until_collection_commit_succeeds(self):
        source = OFFLINE_VIEWS.read_text(encoding="utf-8")
        start = source.index("    private func beginCollection()")
        end = source.find("\n    private var authenticationStatusText", start)
        self.assertGreater(end, start)
        body = source[start:end]

        commit_index = body.index("if model.applyPortalCollection(result)")
        dismiss_index = body.index("showingAuthentication = false")
        self.assertGreater(
            dismiss_index,
            commit_index,
            "the visible WebView must remain mounted while collection is running",
        )
        self.assertLess(
            body.index("showingAuthentication = true"),
            body.index("isCollecting = true"),
            "collection must present the visible authentication surface before starting",
        )
        self.assertIn(
            "pendingCollectionStart",
            source,
            "a collection requested outside the sheet must wait for its WebView to appear",
        )
        self.assertIn(
            "onAppear { beginPendingCollectionIfNeeded() }",
            source,
            "the collection task must start only after the authentication sheet is mounted",
        )
        self.assertIn(
            ".interactiveDismissDisabled(isCollecting)",
            source,
            "the collection sheet must not be swiped away while page JavaScript is active",
        )

    def test_retry_is_consumed_by_one_collection_callback(self):
        source = AUTHENTICATION_VIEW.read_text(encoding="utf-8")
        self.assertIn(
            "self.onPrepareToCollect = onPrepareToCollect ?? {",
            source,
            "the standalone authentication screen must also handle retry state",
        )
        self.assertNotIn(
            "guard model.retryCollection() else { return }\n                        onPrepareToCollect()",
            source,
            "the retry button must not consume the retry transition before the parent callback",
        )


if __name__ == "__main__":
    unittest.main()
