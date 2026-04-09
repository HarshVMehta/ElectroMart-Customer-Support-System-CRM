@isTest
private class WebToCaseControllerTest {

    @isTest
    static void createCaseReturnsStructuredResult() {
        Test.startTest();
        WebToCaseController.CaseCreationResult result = WebToCaseController.createCase(
            'Portal User',
            'portal.user@example.com',
            'Need support with laptop',
            'Laptop is not booting and showing a black screen.',
            'Laptop',
            'Hardware Issue',
            null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Controller should return a non-null response payload.');
        System.assertNotEquals(null, result.caseId, 'Created Case Id should be returned.');
        System.assertNotEquals(null, result.caseNumber, 'Created Case Number should be returned.');
        System.assertEquals(true, result.attachmentsSaved, 'No attachment scenario should be marked as saved.');
        System.assertNotEquals(
            null,
            result.confirmationEmailSent,
            'Email send status should always be returned to support user-facing warnings.'
        );

        Case insertedCase = [
            SELECT Id, Subject, SuppliedEmail
            FROM Case
            WHERE Id = :result.caseId
            LIMIT 1
        ];

        System.assertEquals('Need support with laptop', insertedCase.Subject);
        System.assertEquals('portal.user@example.com', insertedCase.SuppliedEmail);
    }

    @isTest
    static void createCaseRejectsInvalidEmailFormat() {
        Boolean didThrow = false;

        try {
            WebToCaseController.createCase(
                'Portal User',
                'invalid-email',
                'Need support',
                'Description is long enough to pass validation.',
                'Mobile',
                'Hardware Issue',
                null
            );
        } catch (AuraHandledException ex) {
            didThrow = true;
        }

        System.assertEquals(true, didThrow, 'Invalid email should block case creation.');
    }

    @isTest
    static void createCaseSavesValidImageAttachment() {
        String attachmentJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'fileName' => 'screen-shot.png',
                'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('image-bytes')),
                'contentType' => 'image/png'
            }
        });

        Test.startTest();
        WebToCaseController.CaseCreationResult result = WebToCaseController.createCase(
            'Portal User',
            'portal.user@example.com',
            'Attachment test case',
            'Testing attachment upload through web-to-case flow.',
            'Laptop',
            'Hardware Issue',
            attachmentJson
        );
        Test.stopTest();

        System.assertEquals(true, result.attachmentsSaved, 'Attachment upload should be reported as successful.');

        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :result.caseId
        ];
        System.assert(linkCount > 0, 'Attachment should create at least one content document link.');
    }

    @isTest
    static void createCaseHandlesMalformedAttachmentPayload() {
        Test.startTest();
        WebToCaseController.CaseCreationResult result = WebToCaseController.createCase(
            'Portal User',
            'portal.user@example.com',
            'Malformed attachment payload',
            'Attachment JSON is malformed but case should still be created.',
            'Mobile',
            'Software Issue',
            '{"bad":"payload"}'
        );
        Test.stopTest();

        System.assertNotEquals(null, result.caseId, 'Case creation should not fail for malformed attachment payload.');
        System.assertEquals(true, result.attachmentsSaved, 'Malformed payload should be treated as no attachments.');
    }

    @isTest
    static void createCaseHandlesInvalidAttachmentJsonString() {
        Test.startTest();
        WebToCaseController.CaseCreationResult result = WebToCaseController.createCase(
            'Portal User',
            'portal.user@example.com',
            'Invalid attachment JSON string',
            'Attachment JSON cannot be parsed but case should still be created.',
            'Mobile',
            'Other',
            'not-json'
        );
        Test.stopTest();

        System.assertNotEquals(null, result.caseId, 'Case should still be created when attachment JSON is invalid.');
        System.assertEquals(true, result.attachmentsSaved, 'Invalid JSON should degrade to zero attachments.');
    }

    @isTest
    static void createCaseSupportsImageExtensionWhenContentTypeIsMissing() {
        String attachmentJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'fileName' => 'camera-shot.jpeg',
                'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('jpeg-bytes'))
            }
        });

        Test.startTest();
        WebToCaseController.CaseCreationResult result = WebToCaseController.createCase(
            'Portal User',
            'portal.user@example.com',
            'Extension-based attachment handling',
            'Image MIME type is missing but extension is supported.',
            'Laptop',
            'Other',
            attachmentJson
        );
        Test.stopTest();

        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :result.caseId
        ];

        System.assert(linkCount > 0, 'JPEG extension fallback should still save the attachment.');
    }

    @isTest
    static void createCaseSanitizesLongFilenameWithoutExtension() {
        String veryLongName = String.valueOf(Crypto.getRandomLong())
            + 'verylongfilenamewithoutdotverylongfilenamewithoutdotverylongfilenamewithoutdotverylongfilenamewithoutdot';

        String attachmentJson = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'fileName' => veryLongName,
                'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('png-bytes')),
                'contentType' => 'image/png'
            }
        });

        Test.startTest();
        WebToCaseController.CaseCreationResult result = WebToCaseController.createCase(
            'Portal User',
            'portal.user@example.com',
            'Filename sanitization test',
            'Attachment should be saved even when filename is long and has no extension.',
            'Mobile',
            'Other',
            attachmentJson
        );
        Test.stopTest();

        Integer linkCount = [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :result.caseId
        ];

        System.assert(linkCount > 0, 'Long filename without extension should still be sanitized and saved.');
    }

    @isTest
    static void createCaseReturnsWarningsWhenEmailOrAttachmentFails() {
        WebToCaseController.forceConfirmationEmailFailureForTest = true;
        WebToCaseController.forceAttachmentFailureForTest = true;

        try {
            Test.startTest();
            WebToCaseController.CaseCreationResult result = WebToCaseController.createCase(
                'Portal User',
                'portal.user@example.com',
                'Warning branch test',
                'Controller should report warning states when send/save operations fail.',
                'Warranty',
                'Warranty Claim',
                JSON.serialize(new List<Object>{
                    new Map<String, Object>{
                        'fileName' => 'proof.png',
                        'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('proof-bytes')),
                        'contentType' => 'image/png'
                    }
                })
            );
            Test.stopTest();

            System.assertNotEquals(null, result.caseId, 'Case should still be created on warning path.');
            System.assertEquals(false, result.confirmationEmailSent, 'Forced email failure should be reflected in response.');
            System.assertEquals(false, result.attachmentsSaved, 'Forced attachment failure should be reflected in response.');
            System.assert(
                String.isNotBlank(result.confirmationEmailMessage),
                'Warning response should include an email failure reason.'
            );
            System.assert(
                String.isNotBlank(result.attachmentsMessage),
                'Warning response should include an attachment failure reason.'
            );
        } finally {
            WebToCaseController.forceConfirmationEmailFailureForTest = false;
            WebToCaseController.forceAttachmentFailureForTest = false;
        }
    }
}