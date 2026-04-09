@isTest
private class CaseTrackingControllerTest {

    private class StubEmailException extends Exception {}

    @testSetup
    static void setupData() {
        insert new Case(
            Subject = 'Tracking Test Case',
            Description = 'Valid description for case tracking tests.',
            Origin = 'Web',
            Status = 'New',
            Priority = 'Medium',
            SuppliedName = 'Portal User',
            SuppliedEmail = 'portal.user@example.com'
        );
    }

    @isTest
    static void requestOtpStoresOtpState() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '123456';

        Test.startTest();
        CaseTrackingController.OtpRequestResult result =
            CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);
        Test.stopTest();

        System.assertEquals(true, result.success, 'OTP request should succeed.');
        System.assertNotEquals(null, result.maskedEmail, 'Masked email should be returned.');
        System.assertEquals(10 * 60, result.expiresInSeconds, 'OTP expiry should be 10 minutes.');

        Case refreshed = [
            SELECT Tracking_OTP_Hash__c, Tracking_OTP_Expiry__c, Tracking_OTP_Attempts__c, Tracking_OTP_LastSent__c
            FROM Case
            WHERE Id = :testCase.Id
        ];

        System.assertNotEquals(null, refreshed.Tracking_OTP_Hash__c, 'OTP hash must be stored.');
        System.assertNotEquals(null, refreshed.Tracking_OTP_Expiry__c, 'OTP expiry must be stored.');
        System.assertEquals(5, refreshed.Tracking_OTP_Attempts__c.intValue(), 'Attempts should reset to 5.');
        System.assertNotEquals(null, refreshed.Tracking_OTP_LastSent__c, 'Last sent timestamp must be stored.');
    }

    @isTest
    static void verifyOtpReturnsTrackingPayload() {
        Case testCase = [SELECT Id, CaseNumber, Status FROM Case LIMIT 1];
        Datetime publicUpdateTime = System.now().addMinutes(-3);

        testCase.put('Tracking_Public_Stage__c', 'Investigation in Progress');
        testCase.put('Tracking_Public_Update__c', 'Our team has started detailed diagnostics on your issue.');
        testCase.put('Tracking_Public_Update_Time__c', publicUpdateTime);
        update testCase;

        testCase = [SELECT Id, CaseNumber, Status FROM Case WHERE Id = :testCase.Id LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '654321';

        CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);

        Test.startTest();
        CaseTrackingController.VerificationResult verification =
            CaseTrackingController.verifyTrackingOtp(testCase.CaseNumber, '654321');
        Test.stopTest();

        System.assertEquals(true, verification.success, 'OTP verification should succeed.');
        System.assertNotEquals(null, verification.tracking, 'Tracking payload should be returned.');
        System.assertEquals(testCase.CaseNumber, verification.tracking.caseNumber, 'Case number should match.');
        System.assertEquals('Investigation in Progress', verification.tracking.publicStage, 'Public stage should map into payload.');
        System.assertEquals(
            'Our team has started detailed diagnostics on your issue.',
            verification.tracking.publicUpdate,
            'Public update text should map into payload.'
        );
        System.assertEquals(2, verification.tracking.currentStageIndex, 'Custom stage should drive stage index.');
        System.assertNotEquals(null, verification.tracking.stages, 'Stages should be present.');
        System.assert(verification.tracking.stages.size() > 0, 'Stages should not be empty.');
        System.assertEquals(
            'Investigation in Progress',
            verification.tracking.stages[2].label,
            'Pipeline stage labels should reflect configured public stages.'
        );
        System.assertNotEquals(
            null,
            verification.tracking.publicUpdateTime,
            'Public update timestamp should be available in payload.'
        );

        Boolean hasPublicUpdateEntry = false;
        for (CaseTrackingController.TrackingUpdate updateRow : verification.tracking.updates) {
            if (updateRow != null && updateRow.key == 'public-update') {
                hasPublicUpdateEntry = true;
                break;
            }
        }
        System.assertEquals(true, hasPublicUpdateEntry, 'Tracking updates should include the public update entry.');

        Case refreshed = [
            SELECT Tracking_OTP_Hash__c, Tracking_OTP_Expiry__c, Tracking_OTP_Attempts__c
            FROM Case
            WHERE Id = :testCase.Id
        ];

        System.assertEquals(null, refreshed.Tracking_OTP_Hash__c, 'OTP hash should be cleared after verification.');
        System.assertEquals(null, refreshed.Tracking_OTP_Expiry__c, 'OTP expiry should be cleared after verification.');
        System.assertEquals(null, refreshed.Tracking_OTP_Attempts__c, 'OTP attempts should be cleared after verification.');
    }

    @isTest
    static void verifyOtpWithInvalidCodeReducesAttemptCount() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '777777';

        CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);

        Boolean didThrow = false;
        try {
            CaseTrackingController.verifyTrackingOtp(testCase.CaseNumber, '000000');
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Invalid OTP must throw an exception.');

        Case refreshed = [
            SELECT Tracking_OTP_Attempts__c
            FROM Case
            WHERE Id = :testCase.Id
        ];
        System.assertEquals(4, refreshed.Tracking_OTP_Attempts__c.intValue(), 'Attempts should decrease by one.');
    }

    @isTest
    static void requestOtpForUnknownCaseThrows() {
        Boolean didThrow = false;

        try {
            CaseTrackingController.requestTrackingOtp('NO_MATCHING_CASE');
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Unknown case reference should throw an exception.');
    }

    @isTest
    static void requestOtpSupportsCaseIdReference() {
        Case testCase = [SELECT Id FROM Case LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '112233';

        Test.startTest();
        CaseTrackingController.OtpRequestResult result =
            CaseTrackingController.requestTrackingOtp((String) testCase.Id);
        Test.stopTest();

        System.assertEquals(true, result.success, 'Case Id reference should be supported.');
    }

    @isTest
    static void requestOtpEnforcesCooldownWindow() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '334455';

        CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);

        Boolean didThrow = false;
        try {
            CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Immediate resend should fail due to cooldown.');
    }

    @isTest
    static void verifyOtpThrowsWhenExpired() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '556677';

        CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);

        Case staleCase = [
            SELECT Id, Tracking_OTP_Expiry__c
            FROM Case
            WHERE Id = :testCase.Id
        ];
        staleCase.Tracking_OTP_Expiry__c = System.now().addMinutes(-5);
        update staleCase;

        Boolean didThrow = false;
        try {
            CaseTrackingController.verifyTrackingOtp(testCase.CaseNumber, '556677');
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Expired OTP should not be accepted.');
    }

    @isTest
    static void requestOtpFailsWhenCaseHasNoEmail() {
        Case caseWithoutEmail = new Case(
            Subject = 'No Email Case',
            Description = 'Used to cover no email branch.',
            Origin = 'Web',
            Status = 'New',
            Priority = 'Medium'
        );
        insert caseWithoutEmail;

        Boolean didThrow = false;
        try {
            CaseTrackingController.requestTrackingOtp(caseWithoutEmail.CaseNumber);
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Case without email should fail OTP request.');
    }

    @isTest
    static void requestOtpRollsBackWhenEmailDeliveryFails() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '909090';
        CaseTrackingController.forceOtpEmailFailureForTest = true;

        Boolean didThrow = false;

        try {
            CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);
        } catch (Exception ex) {
            didThrow = true;
        } finally {
            CaseTrackingController.forceOtpEmailFailureForTest = false;
        }

        System.assertEquals(true, didThrow, 'OTP request should fail when email delivery fails.');

        Case refreshed = [
            SELECT Tracking_OTP_Hash__c, Tracking_OTP_Expiry__c, Tracking_OTP_Attempts__c, Tracking_OTP_LastSent__c
            FROM Case
            WHERE Id = :testCase.Id
        ];

        System.assertEquals(null, refreshed.Tracking_OTP_Hash__c, 'OTP hash should be cleared when email send fails.');
        System.assertEquals(null, refreshed.Tracking_OTP_Expiry__c, 'OTP expiry should be cleared when email send fails.');
        System.assertEquals(null, refreshed.Tracking_OTP_Attempts__c, 'OTP attempts should be cleared when email send fails.');
        System.assertEquals(null, refreshed.Tracking_OTP_LastSent__c, 'Last sent timestamp should be cleared when email send fails.');
    }

    @isTest
    static void requestOtpRejectsShortReference() {
        Boolean didThrow = false;

        try {
            CaseTrackingController.requestTrackingOtp('123');
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Very short case references should be rejected early.');
    }

    @isTest
    static void verifyOtpRequiresRequestedOtpFirst() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];

        // Ensure OTP fields are empty before verification attempt.
        Case resetCase = [
            SELECT Id, Tracking_OTP_Hash__c, Tracking_OTP_Expiry__c, Tracking_OTP_Attempts__c
            FROM Case
            WHERE Id = :testCase.Id
        ];
        resetCase.Tracking_OTP_Hash__c = null;
        resetCase.Tracking_OTP_Expiry__c = null;
        resetCase.Tracking_OTP_Attempts__c = null;
        update resetCase;

        Boolean didThrow = false;
        try {
            CaseTrackingController.verifyTrackingOtp(testCase.CaseNumber, '123456');
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Verification should fail if OTP was not requested first.');
    }

    @isTest
    static void verifyOtpFailsWhenNoAttemptsLeft() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '135790';

        CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);

        Case exhaustedCase = [
            SELECT Id, Tracking_OTP_Attempts__c
            FROM Case
            WHERE Id = :testCase.Id
        ];
        exhaustedCase.Tracking_OTP_Attempts__c = 0;
        update exhaustedCase;

        Boolean didThrow = false;
        try {
            CaseTrackingController.verifyTrackingOtp(testCase.CaseNumber, '135790');
        } catch (Exception ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Verification should fail when attempts are exhausted.');

        Case refreshed = [
            SELECT Tracking_OTP_Hash__c, Tracking_OTP_Expiry__c
            FROM Case
            WHERE Id = :testCase.Id
        ];
        System.assertEquals(null, refreshed.Tracking_OTP_Hash__c, 'Hash should be cleared when attempts are exhausted.');
        System.assertEquals(null, refreshed.Tracking_OTP_Expiry__c, 'Expiry should be cleared when attempts are exhausted.');
    }

    @isTest
    static void requestOtpFailsWhenEmailCapacityUnavailable() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        CaseTrackingController.forceOtpCapacityFailureForTest = true;

        Boolean didThrow = false;
        try {
            CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);
        } catch (Exception ex) {
            didThrow = true;
        } finally {
            CaseTrackingController.forceOtpCapacityFailureForTest = false;
        }

        System.assertEquals(true, didThrow, 'OTP request should fail when capacity is unavailable.');

        Case refreshed = [
            SELECT Tracking_OTP_Hash__c, Tracking_OTP_Expiry__c, Tracking_OTP_Attempts__c
            FROM Case
            WHERE Id = :testCase.Id
        ];

        System.assertEquals(null, refreshed.Tracking_OTP_Hash__c, 'OTP values should not be persisted when capacity check fails.');
        System.assertEquals(null, refreshed.Tracking_OTP_Expiry__c, 'OTP values should not be persisted when capacity check fails.');
        System.assertEquals(null, refreshed.Tracking_OTP_Attempts__c, 'OTP values should not be persisted when capacity check fails.');
    }

    @isTest
    static void requestOtpSurfacesLimitMessageFromEmailFailure() {
        Case testCase = [SELECT Id, CaseNumber FROM Case LIMIT 1];
        CaseTrackingController.otpOverrideForTest = '246810';
        CaseTrackingController.forceOtpEmailFailureForTest = true;
        CaseTrackingController.forcedOtpEmailFailureMessageForTest = 'single email limit exceeded';

        Boolean didThrow = false;

        try {
            CaseTrackingController.requestTrackingOtp(testCase.CaseNumber);
        } catch (Exception ex) {
            didThrow = true;
        } finally {
            CaseTrackingController.forceOtpEmailFailureForTest = false;
            CaseTrackingController.forcedOtpEmailFailureMessageForTest = null;
        }

        System.assertEquals(true, didThrow, 'OTP request should fail when forced limit-style message is returned.');
    }

    @isTest
    static void resolveOtpEmailFailureMessageCoversBranches() {
        String defaultMessage = CaseTrackingController.resolveOtpEmailFailureMessage(null);
        System.assertEquals(
            'Unable to send OTP email at this time. Please try again.',
            defaultMessage,
            'Null exceptions should map to the default user-friendly message.'
        );

        String limitMessage = CaseTrackingController.resolveOtpEmailFailureMessage(
            new StubEmailException('single email limit exceeded')
        );
        System.assert(
            limitMessage.toLowerCase().contains('daily email limit has been reached'),
            'Limit-related exceptions should map to a daily-limit message.'
        );

        String genericMessage = CaseTrackingController.resolveOtpEmailFailureMessage(
            new StubEmailException('smtp timeout')
        );
        System.assert(
            genericMessage.startsWith('Unable to send OTP email at this time.'),
            'Generic failures should preserve useful downstream error context.'
        );
    }

    @isTest
    static void extractSendEmailErrorHandlesNullAndEmptyResponses() {
        String nullResponseMessage = CaseTrackingController.extractSendEmailError(null);
        System.assertEquals(
            'Email delivery failed without a detailed reason.',
            nullResponseMessage,
            'Null send results should return a fallback message.'
        );

        String emptyResponseMessage = CaseTrackingController.extractSendEmailError(
            new List<Messaging.SendEmailResult>()
        );
        System.assertEquals(
            'Email delivery failed without a detailed reason.',
            emptyResponseMessage,
            'Empty send results should return a fallback message.'
        );
    }
}