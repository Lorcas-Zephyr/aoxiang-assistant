import Foundation
import XCTest
@testable import AoxiangCore

final class AuthenticationStateTests: XCTestCase {
    func testMachineStartsClosedAndOnlyAuthenticationCanOpenCollection() throws {
        var machine = AuthenticationStateMachine()

        XCTAssertEqual(machine.state, .needsLogin)
        XCTAssertFalse(machine.canHandle(.prepareToCollect))

        XCTAssertEqual(
            try machine.handle(.authenticationSucceeded),
            .authenticated
        )
        XCTAssertEqual(
            try machine.handle(.prepareToCollect),
            .readyToCollect
        )
        XCTAssertTrue(machine.state.canCollect)
    }

    func testSmsChallengeIsAnExplicitForegroundPath() throws {
        var machine = AuthenticationStateMachine()

        XCTAssertEqual(
            try machine.handle(.smsRequired),
            .needsSMS
        )
        XCTAssertEqual(
            try machine.handle(.smsVerified),
            .authenticated
        )
        XCTAssertEqual(
            try machine.handle(.prepareToCollect),
            .readyToCollect
        )
    }

    func testCollectionNotReadyAttentionAcknowledgementReturnsAuthenticated() throws {
        var machine = AuthenticationStateMachine(
            initialState: .needsUserAttention(reason: .collectionNotReady)
        )

        XCTAssertEqual(
            try machine.handle(.userAttentionAcknowledged),
            .authenticated
        )
        XCTAssertFalse(machine.state.canCollect)
    }

    func testRejectedCredentialsAndSmsRequireUserAttentionWithoutStoringSecrets() throws {
        var loginMachine = AuthenticationStateMachine()
        XCTAssertEqual(
            try loginMachine.handle(.credentialsRejected),
            .needsUserAttention(reason: .invalidCredentials)
        )
        XCTAssertEqual(
            try loginMachine.handle(.userAttentionAcknowledged),
            .needsLogin
        )

        var smsMachine = AuthenticationStateMachine(initialState: .needsSMS)
        XCTAssertEqual(
            try smsMachine.handle(.smsRejected),
            .needsUserAttention(reason: .invalidSMS)
        )
        XCTAssertEqual(
            try smsMachine.handle(.userAttentionAcknowledged),
            .needsSMS
        )

        let encoded = try JSONEncoder().encode(
            AuthenticationState.needsUserAttention(reason: .invalidSMS)
        )
        let serialized = String(decoding: encoded, as: UTF8.self).lowercased()
        XCTAssertFalse(serialized.contains("password"))
        XCTAssertFalse(serialized.contains("cookie"))
        XCTAssertFalse(serialized.contains("123456"))
    }

    func testAuthenticationExpiryEscalatesInsteadOfPretendingCollectionIsReady() throws {
        var machine = AuthenticationStateMachine(initialState: .readyToCollect)

        XCTAssertEqual(
            try machine.handle(.authenticationExpired),
            .needsUserAttention(reason: .authenticationExpired)
        )
        XCTAssertFalse(machine.state.canCollect)

        XCTAssertEqual(
            try machine.handle(.userAttentionAcknowledged),
            .needsLogin
        )
    }

    func testRetryableFailuresKeepAnExplicitRecoveryTarget() throws {
        var loginMachine = AuthenticationStateMachine()
        let loginFailure = RetryableAuthenticationFailure(
            operation: .login,
            reason: .networkUnavailable
        )
        XCTAssertEqual(
            try loginMachine.handle(.retryableFailure(loginFailure)),
            .retryableFailure(loginFailure)
        )
        XCTAssertEqual(
            try loginMachine.handle(.retry),
            .needsLogin
        )

        var collectionMachine = AuthenticationStateMachine(initialState: .readyToCollect)
        let collectionFailure = RetryableAuthenticationFailure(
            operation: .collection,
            reason: .serverUnavailable
        )
        XCTAssertEqual(
            try collectionMachine.handle(.retryableFailure(collectionFailure)),
            .retryableFailure(collectionFailure)
        )
        XCTAssertEqual(
            try collectionMachine.handle(.retry),
            .readyToCollect
        )
    }

    func testIllegalTransitionLeavesStateUnchangedAndIsObservable() {
        var machine = AuthenticationStateMachine()

        XCTAssertThrowsError(try machine.handle(.smsVerified)) { error in
            XCTAssertEqual(
                error as? AuthenticationTransitionError,
                .invalidTransition(from: .needsLogin, event: .smsVerified)
            )
        }
        XCTAssertEqual(machine.state, .needsLogin)

        XCTAssertThrowsError(try machine.handle(.retry)) { error in
            XCTAssertEqual(
                error as? AuthenticationTransitionError,
                .invalidTransition(from: .needsLogin, event: .retry)
            )
        }
        XCTAssertEqual(machine.state, .needsLogin)
    }

    func testBackgroundCanRecordSmsAsPendingUserAttention() throws {
        var machine = AuthenticationStateMachine(initialState: .needsSMS)

        XCTAssertEqual(
            try machine.handle(.userAttentionRequired(.smsRequired)),
            .needsUserAttention(reason: .smsRequired)
        )
        XCTAssertEqual(
            try machine.handle(.userAttentionAcknowledged),
            .needsSMS
        )
    }

    func testStateRoundTripIsStableAndContainsOnlyNonSecretMetadata() throws {
        let states: [AuthenticationState] = [
            .needsLogin,
            .needsSMS,
            .authenticated,
            .readyToCollect,
            .retryableFailure(
                RetryableAuthenticationFailure(
                    operation: .collection,
                    reason: .rateLimited
                )
            ),
            .needsUserAttention(reason: .authenticationExpired),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for state in states {
            let data = try encoder.encode(state)
            XCTAssertEqual(try decoder.decode(AuthenticationState.self, from: data), state)
            let json = String(decoding: data, as: UTF8.self).lowercased()
            XCTAssertFalse(json.contains("password"))
            XCTAssertFalse(json.contains("cookie"))
            XCTAssertFalse(json.contains("token"))
            XCTAssertFalse(json.contains("credential"))
            XCTAssertFalse(json.contains("123456"))
        }
    }
}
