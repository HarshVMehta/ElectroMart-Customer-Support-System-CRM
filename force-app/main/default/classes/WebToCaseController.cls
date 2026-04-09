public with sharing class WebToCaseController {

    public class AttachmentUploadRequest {
        @AuraEnabled public String fileName;
        @AuraEnabled public String base64Data;
        @AuraEnabled public String contentType;
    }

    public class CaseCreationResult {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public Boolean confirmationEmailSent;
        @AuraEnabled public String confirmationEmailMessage;
        @AuraEnabled public Boolean attachmentsSaved;
        @AuraEnabled public String attachmentsMessage;
    }

    private class EmailDeliveryResult {
        public Boolean success;
        public String message;
    }

    private static final Integer MAX_ATTACHMENTS = 3;
    private static final Integer MAX_ATTACHMENT_SIZE_BYTES = 2 * 1024 * 1024;
    private static final Integer MAX_TOTAL_ATTACHMENT_BYTES = 4 * 1024 * 1024;

    @TestVisible
    private static Boolean forceConfirmationEmailFailureForTest = false;

    @TestVisible
    private static Boolean forceAttachmentFailureForTest = false;

    /**
     * Create a Support Case from Web-to-Case form submission
     * @param name - Customer name
     * @param email - Customer email
     * @param subject - Case subject
     * @param description - Detailed issue description
     * @param product - Product category
     * @param issueType - Type of issue
        * @param attachmentsJson - Optional JSON array payload of image attachments
         * @return Case creation response with delivery diagnostics
     */
    @AuraEnabled
        public static CaseCreationResult createCase(String name, String email, String subject,
                                                                                                String description, String product, String issueType,
                                                                                                String attachmentsJson) {
        try {
            // Input Validation
            if (String.isBlank(name) || String.isBlank(email) || 
                String.isBlank(subject) || String.isBlank(description) ||
                String.isBlank(product) || String.isBlank(issueType)) {
                throw new AuraHandledException('All fields are required');
            }

            // Validate Email Format
            if (!isValidEmail(email)) {
                throw new AuraHandledException('Invalid email format');
            }

            // Create Case
            Case c = new Case();
            c.Subject = subject.trim();
            c.Description = description.trim();
            c.Origin = 'Web';
            c.Priority = 'Medium';
            c.Status = 'New';
            c.SuppliedName = name.trim();
            c.SuppliedEmail = email.trim();

            // Attempt to set custom fields if they exist (non-blocking)
            try {
                c.put('Product__c', product);
                c.put('Issue_Category__c', issueType);
            } catch (Exception e) {
                // Custom fields don't exist, but case can still be created
                System.debug('Custom fields not available: ' + e.getMessage());
            }

            // Insert the case
            insert c;

            CaseCreationResult response = new CaseCreationResult();
            response.caseId = c.Id;
            response.caseNumber = c.CaseNumber;
            response.attachmentsSaved = true;
            response.attachmentsMessage = 'No attachments uploaded.';
            response.confirmationEmailSent = false;
            response.confirmationEmailMessage = 'Confirmation email was not attempted.';

            List<AttachmentUploadRequest> attachments = parseAttachmentRequests(attachmentsJson);
            if (!attachments.isEmpty()) {
                response.attachmentsMessage = 'Attachments uploaded successfully.';
            }

            // Save optional attachments to the case (best-effort, non-blocking)
            try {
                if (Test.isRunningTest() && forceAttachmentFailureForTest) {
                    throw new AuraHandledException('Forced attachment failure for coverage.');
                }

                saveCaseAttachments(c.Id, attachments);
            } catch (Exception attachmentEx) {
                response.attachmentsSaved = false;
                response.attachmentsMessage = 'Attachments could not be saved. ' + safeExceptionMessage(attachmentEx);
                System.debug('Case created but attachment upload failed: ' + safeExceptionMessage(attachmentEx));
            }

            // Send confirmation email to customer and return explicit outcome to the UI.
            EmailDeliveryResult emailResult = sendCaseCreationEmail(c);
            response.confirmationEmailSent = emailResult.success;
            response.confirmationEmailMessage = emailResult.message;

            if (String.isBlank(response.caseNumber)) {
                response.caseNumber = composeCaseIdentifier(c.Id);
            }

            System.debug('Case created successfully with ID: ' + c.Id);
            return response;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug('Error creating case: ' + e.getMessage());
            throw new AuraHandledException('Unable to create case: ' + e.getMessage());
        }
    }

    /**
     * Validate Email Address Format
     * @param email - Email to validate
     * @return Boolean - true if valid email format
     */
    private static Boolean isValidEmail(String email) {
        String emailPattern = '^[a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,4}$';
        Pattern p = Pattern.compile(emailPattern);
        Matcher m = p.matcher(email);
        return m.matches();
    }

    /**
     * Parses attachment JSON payload from LWC into typed wrapper rows.
     */
    private static List<AttachmentUploadRequest> parseAttachmentRequests(String attachmentsJson) {
        List<AttachmentUploadRequest> parsedRequests = new List<AttachmentUploadRequest>();

        if (String.isBlank(attachmentsJson)) {
            return parsedRequests;
        }

        Object raw;
        try {
            raw = JSON.deserializeUntyped(attachmentsJson);
        } catch (Exception ex) {
            return parsedRequests;
        }

        if (!(raw instanceof List<Object>)) {
            return parsedRequests;
        }

        List<Object> rows = (List<Object>) raw;
        for (Object row : rows) {
            if (!(row instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> values = (Map<String, Object>) row;

            AttachmentUploadRequest request = new AttachmentUploadRequest();
            request.fileName = values.containsKey('fileName') ? String.valueOf(values.get('fileName')) : null;
            request.base64Data = values.containsKey('base64Data') ? String.valueOf(values.get('base64Data')) : null;
            request.contentType = values.containsKey('contentType') ? String.valueOf(values.get('contentType')) : null;

            parsedRequests.add(request);
        }

        return parsedRequests;
    }

    /**
     * Creates ContentVersion records and links them to the case using FirstPublishLocationId.
     * Accepts only image files and enforces conservative limits.
     */
    private static void saveCaseAttachments(Id caseId, List<AttachmentUploadRequest> attachments) {
        if (caseId == null || attachments == null || attachments.isEmpty()) {
            return;
        }

        List<ContentVersion> versionsToInsert = new List<ContentVersion>();
        Integer uploadedCount = 0;
        Integer totalBytes = 0;

        for (AttachmentUploadRequest upload : attachments) {
            if (uploadedCount >= MAX_ATTACHMENTS) {
                break;
            }

            if (upload == null || String.isBlank(upload.fileName) || String.isBlank(upload.base64Data)) {
                continue;
            }

            String normalizedType = String.isBlank(upload.contentType)
                ? ''
                : upload.contentType.toLowerCase();

            if (!isSupportedImageType(normalizedType, upload.fileName)) {
                continue;
            }

            Blob body;
            try {
                body = EncodingUtil.base64Decode(upload.base64Data);
            } catch (Exception decodeEx) {
                continue;
            }

            if (body == null) {
                continue;
            }

            Integer fileSize = body.size();
            if (fileSize <= 0 || fileSize > MAX_ATTACHMENT_SIZE_BYTES) {
                continue;
            }

            if (totalBytes + fileSize > MAX_TOTAL_ATTACHMENT_BYTES) {
                break;
            }

            String fileName = sanitizeFileName(upload.fileName);
            String title = deriveFileTitle(fileName);

            versionsToInsert.add(new ContentVersion(
                Title = title,
                PathOnClient = '/' + fileName,
                VersionData = body,
                FirstPublishLocationId = caseId,
                IsMajorVersion = true
            ));

            uploadedCount++;
            totalBytes += fileSize;
        }

        if (!versionsToInsert.isEmpty()) {
            insert versionsToInsert;
        }
    }

    private static Boolean isSupportedImageType(String normalizedType, String fileName) {
        if (String.isNotBlank(normalizedType) && normalizedType.startsWith('image/')) {
            return true;
        }

        String lowerFileName = String.isBlank(fileName) ? '' : fileName.toLowerCase();
        return lowerFileName.endsWith('.png')
            || lowerFileName.endsWith('.jpg')
            || lowerFileName.endsWith('.jpeg')
            || lowerFileName.endsWith('.gif')
            || lowerFileName.endsWith('.webp')
            || lowerFileName.endsWith('.bmp')
            || lowerFileName.endsWith('.heic');
    }

    private static String sanitizeFileName(String fileName) {
        String normalized = String.isBlank(fileName)
            ? 'attachment-image.png'
            : fileName.trim();

        if (normalized.length() > 120) {
            normalized = normalized.substring(0, 120);
        }

        if (!normalized.contains('.')) {
            normalized += '.png';
        }

        return normalized;
    }

    private static String deriveFileTitle(String fileName) {
        if (String.isBlank(fileName)) {
            return 'attachment-image';
        }

        Integer dotIndex = fileName.lastIndexOf('.');
        if (dotIndex <= 0) {
            return fileName;
        }

        return fileName.substring(0, dotIndex);
    }

    /**
     * Sends a confirmation email to the supplied customer email after case creation.
     * Includes case identifiers that can be used for status tracking.
     */
    private static EmailDeliveryResult sendCaseCreationEmail(Case createdCase) {
        EmailDeliveryResult response = new EmailDeliveryResult();

        if (Test.isRunningTest() && forceConfirmationEmailFailureForTest) {
            response.success = false;
            response.message = 'Forced confirmation email failure for coverage.';
            return response;
        }

        if (createdCase == null || String.isBlank(createdCase.SuppliedEmail)) {
            response.success = false;
            response.message = 'No recipient email was available on the case.';
            return response;
        }

        try {
            Messaging.reserveSingleEmailCapacity(1);
        } catch (Exception capacityEx) {
            response.success = false;
            response.message = 'Salesforce daily email limit has been reached. Please try again after reset.';
            return response;
        }

        String customerName = String.isBlank(createdCase.SuppliedName) ? 'Customer' : createdCase.SuppliedName;
        String caseNumber = createdCase.CaseNumber;

        if (String.isBlank(caseNumber)) {
            caseNumber = composeCaseIdentifier(createdCase.Id);
        }

        String displayCaseNumber = String.isBlank(caseNumber) ? 'N/A' : caseNumber;

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ createdCase.SuppliedEmail.trim() });
        mail.setSubject('ElectroMart Support Request Created - Case ' + displayCaseNumber);
        mail.setPlainTextBody(
            'Hello ' + customerName + ',\n\n'
            + 'Your support request has been created successfully.\n\n'
            + 'This is your case ID: ' + String.valueOf(createdCase.Id) + '\n'
            + 'Case Number: ' + displayCaseNumber + '\n\n'
            + 'With this case ID/number, you can check the status of your case in the support portal.\n\n'
            + 'Thank you,\n'
            + 'ElectroMart Support Team'
        );

        Messaging.SendEmailResult[] results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        if (results == null || results.isEmpty() || !results[0].isSuccess()) {
            response.success = false;
            response.message = extractSendEmailError(results);
            System.debug('Confirmation email could not be sent for case: ' + createdCase.Id + '. Reason: ' + response.message);
            return response;
        }

        response.success = true;
        response.message = 'Confirmation email sent successfully.';
        return response;
    }

    private static String composeCaseIdentifier(Id caseId) {
        if (caseId == null) {
            return null;
        }

        Case reloadedCase = [
            SELECT Id, CaseNumber
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        return reloadedCase.CaseNumber;
    }

    private static String extractSendEmailError(Messaging.SendEmailResult[] results) {
        if (results == null || results.isEmpty() || results[0] == null) {
            return 'Salesforce could not provide an email failure reason.';
        }

        Messaging.SendEmailResult firstResult = results[0];
        if (firstResult.isSuccess()) {
            return 'Email sent successfully.';
        }

        if (firstResult.getErrors() == null || firstResult.getErrors().isEmpty()) {
            return 'Email delivery failed without a detailed reason.';
        }

        List<String> messages = new List<String>();
        for (Messaging.SendEmailError sendError : firstResult.getErrors()) {
            if (sendError != null && String.isNotBlank(sendError.getMessage())) {
                messages.add(sendError.getMessage());
            }
        }

        return messages.isEmpty()
            ? 'Email delivery failed without a detailed reason.'
            : String.join(messages, ' | ');
    }

    private static String safeExceptionMessage(Exception ex) {
        if (ex == null || String.isBlank(ex.getMessage())) {
            return 'Unexpected error occurred.';
        }

        return ex.getMessage();
    }
}