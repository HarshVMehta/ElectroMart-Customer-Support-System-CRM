public without sharing class CaseTrackingController {

    private static final Integer OTP_LENGTH = 6;
    private static final Integer OTP_EXPIRY_MINUTES = 10;
    private static final Integer OTP_RESEND_COOLDOWN_SECONDS = 45;
    private static final Integer OTP_MAX_ATTEMPTS = 5;

    @TestVisible
    private static String otpOverrideForTest;

    @TestVisible
    private static Boolean forceOtpEmailFailureForTest = false;

    @TestVisible
    private static String forcedOtpEmailFailureMessageForTest;

    @TestVisible
    private static Boolean forceOtpCapacityFailureForTest = false;

    public class OtpRequestResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String maskedEmail;
        @AuraEnabled public Integer expiresInSeconds;
        @AuraEnabled public Integer resendAvailableInSeconds;
    }

    public class VerificationResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public CaseTrackingPayload tracking;
    }

    public class CaseTrackingPayload {
        @AuraEnabled public Id caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Boolean isClosed;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastUpdatedDate;
        @AuraEnabled public Datetime closedDate;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String publicStage;
        @AuraEnabled public String publicUpdate;
        @AuraEnabled public Datetime publicUpdateTime;
        @AuraEnabled public Integer currentStageIndex;
        @AuraEnabled public List<TrackingStage> stages;
        @AuraEnabled public List<TrackingUpdate> updates;
    }

    public class TrackingStage {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String description;
        @AuraEnabled public Boolean completed;
        @AuraEnabled public Boolean current;
        @AuraEnabled public Datetime timestamp;
    }

    public class TrackingUpdate {
        @AuraEnabled public String key;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public Datetime timestamp;
        @AuraEnabled public String tone;
    }

    @AuraEnabled
    public static OtpRequestResult requestTrackingOtp(String caseReference) {
        String normalizedReference = normalizeReference(caseReference);
        Case trackedCase = getCaseByReference(normalizedReference);
        String recipientEmail = resolveRecipientEmail(trackedCase);

        Datetime nowValue = System.now();
        Integer secondsToWait = getRemainingCooldownSeconds(trackedCase, nowValue);
        if (secondsToWait > 0) {
            throw new AuraHandledException('Please wait ' + secondsToWait + ' seconds before requesting a new OTP.');
        }

        ensureOtpEmailCapacity();

        String otpCode = generateOtpCode();
        trackedCase.Tracking_OTP_Hash__c = buildOtpHash(trackedCase.Id, otpCode);
        trackedCase.Tracking_OTP_Expiry__c = nowValue.addMinutes(OTP_EXPIRY_MINUTES);
        trackedCase.Tracking_OTP_Attempts__c = OTP_MAX_ATTEMPTS;
        trackedCase.Tracking_OTP_LastSent__c = nowValue;
        update trackedCase;

        try {
            sendOtpEmail(trackedCase, recipientEmail, otpCode);
        } catch (Exception emailEx) {
            clearOtpFields(trackedCase);
            trackedCase.Tracking_OTP_LastSent__c = null;

            try {
                update trackedCase;
            } catch (Exception cleanupEx) {
                System.debug('Failed to rollback OTP state after email failure: ' + cleanupEx.getMessage());
            }

            throw new AuraHandledException(resolveOtpEmailFailureMessage(emailEx));
        }

        OtpRequestResult response = new OtpRequestResult();
        response.success = true;
        response.message = 'An OTP has been sent to your registered email address.';
        response.maskedEmail = maskEmail(recipientEmail);
        response.expiresInSeconds = OTP_EXPIRY_MINUTES * 60;
        response.resendAvailableInSeconds = OTP_RESEND_COOLDOWN_SECONDS;
        return response;
    }

    @AuraEnabled
    public static VerificationResult verifyTrackingOtp(String caseReference, String otpCode) {
        String normalizedReference = normalizeReference(caseReference);
        String normalizedOtp = normalizeOtp(otpCode);

        Case trackedCase = getCaseByReference(normalizedReference);

        if (String.isBlank(trackedCase.Tracking_OTP_Hash__c) || trackedCase.Tracking_OTP_Expiry__c == null) {
            throw new AuraHandledException('Please request an OTP first.');
        }

        Datetime nowValue = System.now();
        if (trackedCase.Tracking_OTP_Expiry__c < nowValue) {
            clearOtpFields(trackedCase);
            update trackedCase;
            throw new AuraHandledException('OTP expired. Please request a new OTP.');
        }

        Integer attemptsLeft = trackedCase.Tracking_OTP_Attempts__c == null
            ? 0
            : trackedCase.Tracking_OTP_Attempts__c.intValue();

        if (attemptsLeft <= 0) {
            clearOtpFields(trackedCase);
            update trackedCase;
            throw new AuraHandledException('No OTP attempts left. Please request a new OTP.');
        }

        String enteredHash = buildOtpHash(trackedCase.Id, normalizedOtp);
        if (enteredHash != trackedCase.Tracking_OTP_Hash__c) {
            attemptsLeft = attemptsLeft - 1;
            trackedCase.Tracking_OTP_Attempts__c = attemptsLeft;

            if (attemptsLeft <= 0) {
                trackedCase.Tracking_OTP_Hash__c = null;
                trackedCase.Tracking_OTP_Expiry__c = null;
            }

            update trackedCase;

            if (attemptsLeft > 0) {
                throw new AuraHandledException('Invalid OTP. Attempts left: ' + attemptsLeft + '.');
            }

            throw new AuraHandledException('Invalid OTP. No attempts left. Request a new OTP.');
        }

        clearOtpFields(trackedCase);
        update trackedCase;

        VerificationResult response = new VerificationResult();
        response.success = true;
        response.message = 'OTP verified successfully.';
        response.tracking = buildTrackingPayload(trackedCase);
        return response;
    }

    private static Integer getRemainingCooldownSeconds(Case trackedCase, Datetime nowValue) {
        if (trackedCase.Tracking_OTP_LastSent__c == null) {
            return 0;
        }

        Long elapsedMilliseconds = nowValue.getTime() - trackedCase.Tracking_OTP_LastSent__c.getTime();
        Integer elapsedSeconds = Integer.valueOf(elapsedMilliseconds / 1000);

        if (elapsedSeconds >= OTP_RESEND_COOLDOWN_SECONDS) {
            return 0;
        }

        return OTP_RESEND_COOLDOWN_SECONDS - elapsedSeconds;
    }

    private static void clearOtpFields(Case trackedCase) {
        trackedCase.Tracking_OTP_Hash__c = null;
        trackedCase.Tracking_OTP_Expiry__c = null;
        trackedCase.Tracking_OTP_Attempts__c = null;
    }

    private static String normalizeReference(String caseReference) {
        String normalized = caseReference == null ? '' : caseReference.trim();

        if (String.isBlank(normalized) || normalized.length() < 4) {
            throw new AuraHandledException('Enter a valid Case Number or Case ID.');
        }

        return normalized;
    }

    private static String normalizeOtp(String otpCode) {
        String digitsOnly = otpCode == null ? '' : otpCode.replaceAll('[^0-9]', '');

        if (digitsOnly.length() != OTP_LENGTH) {
            throw new AuraHandledException('Enter the ' + OTP_LENGTH + '-digit OTP sent to your email.');
        }

        return digitsOnly;
    }

    private static Case getCaseByReference(String caseReference) {
        Case matchedCase;

        if (isLikelyCaseId(caseReference)) {
            try {
                Id caseId = (Id) caseReference;
                List<Case> byId = queryCases('Id = :caseId', caseId, null);
                if (!byId.isEmpty()) {
                    matchedCase = byId[0];
                }
            } catch (Exception e) {
                matchedCase = null;
            }
        }

        if (matchedCase == null) {
            List<Case> byNumber = queryCases('CaseNumber = :caseNumber', null, caseReference);
            if (!byNumber.isEmpty()) {
                matchedCase = byNumber[0];
            }
        }

        if (matchedCase == null) {
            throw new AuraHandledException('No case found for the provided reference.');
        }

        return matchedCase;
    }

    private static List<Case> queryCases(String filterClause, Id caseId, String caseNumber) {
        String baseSoql =
            'SELECT Id, CaseNumber, Subject, Status, Priority, IsClosed, CreatedDate, LastModifiedDate, ClosedDate, '
            + 'SuppliedEmail, Contact.Email, Owner.Name, '
            + 'Tracking_OTP_Hash__c, Tracking_OTP_Expiry__c, Tracking_OTP_Attempts__c, Tracking_OTP_LastSent__c, '
            + 'Tracking_Public_Stage__c, Tracking_Public_Update__c, Tracking_Public_Update_Time__c '
            + 'FROM Case WHERE ' + filterClause + ' LIMIT 1';

        if (caseId != null) {
            return Database.query(baseSoql);
        }

        return Database.query(baseSoql);
    }

    private static Boolean isLikelyCaseId(String value) {
        if (String.isBlank(value) || !value.startsWith('500')) {
            return false;
        }

        return Pattern.matches('^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$', value);
    }

    private static String resolveRecipientEmail(Case trackedCase) {
        if (trackedCase == null) {
            return null;
        }

        if (String.isNotBlank(trackedCase.SuppliedEmail)) {
            return trackedCase.SuppliedEmail.trim();
        }

        if (trackedCase.Contact != null && String.isNotBlank(trackedCase.Contact.Email)) {
            return trackedCase.Contact.Email.trim();
        }

        throw new AuraHandledException('No email is associated with this case. Please contact support.');
    }

    private static String generateOtpCode() {
        if (Test.isRunningTest() && String.isNotBlank(otpOverrideForTest)) {
            return otpOverrideForTest;
        }

        String otpCode = '';
        for (Integer index = 0; index < OTP_LENGTH; index++) {
            Long randomValue = Crypto.getRandomInteger();
            if (randomValue < 0) {
                randomValue = randomValue * -1;
            }

            Integer digit = Integer.valueOf(Math.mod(randomValue, 10));
            otpCode += String.valueOf(digit);
        }

        return otpCode;
    }

    private static String buildOtpHash(Id caseId, String otpCode) {
        Blob digest = Crypto.generateDigest(
            'SHA-256',
            Blob.valueOf(String.valueOf(caseId) + ':' + otpCode + ':' + UserInfo.getOrganizationId())
        );
        return EncodingUtil.convertToHex(digest);
    }

    private static String maskEmail(String emailAddress) {
        if (String.isBlank(emailAddress) || !emailAddress.contains('@')) {
            return '***';
        }

        List<String> parts = emailAddress.split('@');
        if (parts.size() != 2) {
            return '***';
        }

        String localPart = parts[0];
        String domain = parts[1];

        String maskedLocal = maskPart(localPart);

        Integer dotPosition = domain.lastIndexOf('.');
        String domainRoot = dotPosition > 0 ? domain.substring(0, dotPosition) : domain;
        String tld = dotPosition > 0 ? domain.substring(dotPosition) : '';
        String maskedDomain = maskPart(domainRoot) + tld;

        return maskedLocal + '@' + maskedDomain;
    }

    private static String maskPart(String value) {
        if (String.isBlank(value)) {
            return '***';
        }

        if (value.length() == 1) {
            return value.substring(0, 1) + '*';
        }

        if (value.length() == 2) {
            return value.substring(0, 1) + '*';
        }

        return value.substring(0, 1) + '***' + value.substring(value.length() - 1);
    }

    private static void sendOtpEmail(Case trackedCase, String recipientEmail, String otpCode) {
        if (Test.isRunningTest() && forceOtpEmailFailureForTest) {
            String forcedMessage = String.isBlank(forcedOtpEmailFailureMessageForTest)
                ? 'Forced OTP email failure for coverage.'
                : forcedOtpEmailFailureMessageForTest;
            throw new AuraHandledException(forcedMessage);
        }

        if (trackedCase == null || String.isBlank(recipientEmail) || String.isBlank(otpCode)) {
            return;
        }

        Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
        emailMessage.setToAddresses(new List<String>{ recipientEmail });
        emailMessage.setSubject('ElectroMart Case Tracking OTP - Case ' + trackedCase.CaseNumber);
        emailMessage.setPlainTextBody(
            'Hello,\n\n'
            + 'We received a request to view updates for your support case.\n\n'
            + 'Case Number: ' + trackedCase.CaseNumber + '\n'
            + 'Case ID: ' + trackedCase.Id + '\n'
            + 'Your OTP: ' + otpCode + '\n\n'
            + 'This OTP is valid for ' + OTP_EXPIRY_MINUTES + ' minutes.\n'
            + 'If you did not request this, please ignore this email.\n\n'
            + 'Thank you,\n'
            + 'ElectroMart Support Team'
        );
        emailMessage.setSaveAsActivity(false);

        Messaging.SendEmailResult[] sendResults = Messaging.sendEmail(
            new List<Messaging.SingleEmailMessage>{ emailMessage },
            false
        );

        if (sendResults == null || sendResults.isEmpty() || !sendResults[0].isSuccess()) {
            throw new AuraHandledException(extractSendEmailError(sendResults));
        }
    }

    private static void ensureOtpEmailCapacity() {
        if (Test.isRunningTest() && forceOtpCapacityFailureForTest) {
            throw new AuraHandledException(
                'Salesforce daily email limit has been reached. Please try again after reset.'
            );
        }

        try {
            Messaging.reserveSingleEmailCapacity(1);
        } catch (Exception capacityEx) {
            throw new AuraHandledException(
                'Salesforce daily email limit has been reached. Please try again after reset.'
            );
        }
    }

    @TestVisible
    private static String resolveOtpEmailFailureMessage(Exception emailEx) {
        if (emailEx == null || String.isBlank(emailEx.getMessage())) {
            return 'Unable to send OTP email at this time. Please try again.';
        }

        String rawMessage = emailEx.getMessage();
        String normalized = rawMessage.toLowerCase();

        if (normalized.contains('single email') || normalized.contains('limit')) {
            return 'Salesforce daily email limit has been reached. Please try again after reset.';
        }

        return 'Unable to send OTP email at this time. ' + rawMessage;
    }

    @TestVisible
    private static String extractSendEmailError(Messaging.SendEmailResult[] sendResults) {
        if (sendResults == null || sendResults.isEmpty() || sendResults[0] == null) {
            return 'Email delivery failed without a detailed reason.';
        }

        Messaging.SendEmailResult firstResult = sendResults[0];
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

    private static CaseTrackingPayload buildTrackingPayload(Case trackedCase) {
        CaseTrackingPayload payload = new CaseTrackingPayload();
        payload.caseId = trackedCase.Id;
        payload.caseNumber = trackedCase.CaseNumber;
        payload.subject = trackedCase.Subject;
        payload.status = trackedCase.Status;
        payload.priority = trackedCase.Priority;
        payload.isClosed = trackedCase.IsClosed;
        payload.createdDate = trackedCase.CreatedDate;
        payload.lastUpdatedDate = trackedCase.LastModifiedDate;
        payload.closedDate = trackedCase.ClosedDate;
        payload.ownerName = trackedCase.Owner == null ? null : trackedCase.Owner.Name;
        payload.publicStage = (String) trackedCase.get('Tracking_Public_Stage__c');
        payload.publicUpdate = (String) trackedCase.get('Tracking_Public_Update__c');
        payload.publicUpdateTime = (Datetime) trackedCase.get('Tracking_Public_Update_Time__c');

        payload.currentStageIndex = resolveStageIndex(payload.publicStage, trackedCase.Status, trackedCase.IsClosed);
        payload.stages = buildStages(trackedCase, payload.currentStageIndex, payload.publicUpdateTime);
        payload.updates = buildUpdates(trackedCase);

        return payload;
    }

    private static Integer resolveStageIndex(String publicStage, String caseStatus, Boolean isClosed) {
        if (isClosed == true) {
            return 4;
        }

        String normalizedPublicStage = publicStage == null ? '' : publicStage.trim().toLowerCase();
        if (normalizedPublicStage == 'request received') {
            return 0;
        }

        if (normalizedPublicStage == 'case review started') {
            return 1;
        }

        if (normalizedPublicStage == 'investigation in progress') {
            return 2;
        }

        if (normalizedPublicStage == 'resolution in progress') {
            return 3;
        }

        if (normalizedPublicStage == 'case closed') {
            return 4;
        }

        String normalizedStatus = caseStatus == null ? '' : caseStatus.toLowerCase();

        if (
            normalizedStatus.contains('new')
            || normalizedStatus.contains('open')
            || normalizedStatus.contains('created')
        ) {
            return 0;
        }

        if (
            normalizedStatus.contains('triage')
            || normalizedStatus.contains('assigned')
            || normalizedStatus.contains('review')
        ) {
            return 1;
        }

        if (
            normalizedStatus.contains('working')
            || normalizedStatus.contains('progress')
            || normalizedStatus.contains('escalat')
        ) {
            return 2;
        }

        if (
            normalizedStatus.contains('pending')
            || normalizedStatus.contains('wait')
            || normalizedStatus.contains('hold')
        ) {
            return 3;
        }

        if (normalizedStatus.contains('resolved') || normalizedStatus.contains('closed')) {
            return 4;
        }

        return 2;
    }

    private static List<TrackingStage> buildStages(Case trackedCase, Integer currentStageIndex, Datetime publicUpdateTime) {
        List<String> stageLabels = new List<String>{
            'Request Received',
            'Case Review Started',
            'Investigation in Progress',
            'Resolution in Progress',
            'Case Closed'
        };

        List<String> stageDescriptions = new List<String>{
            'Your request has been logged in our support system.',
            'Our support team has started reviewing your case details.',
            'We are actively diagnosing and investigating the issue.',
            'A resolution is being worked on and prepared for you.',
            'The case has been resolved and closed.'
        };

        List<TrackingStage> stages = new List<TrackingStage>();

        for (Integer index = 0; index < stageLabels.size(); index++) {
            TrackingStage stage = new TrackingStage();
            stage.key = 'stage-' + String.valueOf(index);
            stage.label = stageLabels[index];
            stage.description = stageDescriptions[index];
            stage.completed = index < currentStageIndex;
            stage.current = index == currentStageIndex;
            stage.timestamp = resolveStageTimestamp(trackedCase, index, currentStageIndex, publicUpdateTime);
            stages.add(stage);
        }

        return stages;
    }

    private static Datetime resolveStageTimestamp(
        Case trackedCase,
        Integer stageIndex,
        Integer currentStageIndex,
        Datetime publicUpdateTime
    ) {
        if (stageIndex == 0) {
            return trackedCase.CreatedDate;
        }

        if (stageIndex == 4) {
            return trackedCase.ClosedDate;
        }

        if (stageIndex <= currentStageIndex) {
            if (publicUpdateTime != null) {
                return publicUpdateTime;
            }

            return trackedCase.LastModifiedDate;
        }

        return null;
    }

    private static List<TrackingUpdate> buildUpdates(Case trackedCase) {
        List<TrackingUpdate> updates = new List<TrackingUpdate>();

        String publicStage = (String) trackedCase.get('Tracking_Public_Stage__c');
        String publicUpdate = (String) trackedCase.get('Tracking_Public_Update__c');
        Datetime publicUpdateTime = (Datetime) trackedCase.get('Tracking_Public_Update_Time__c');

        if (String.isNotBlank(publicUpdate)) {
            updates.add(createUpdate(
                'public-update',
                'Latest Support Update',
                publicUpdate,
                publicUpdateTime == null ? trackedCase.LastModifiedDate : publicUpdateTime,
                trackedCase.IsClosed ? 'success' : 'info'
            ));
        }

        if (String.isNotBlank(publicStage)) {
            updates.add(createUpdate(
                'public-stage',
                'Current Stage: ' + publicStage,
                'Your case is currently in this customer-facing stage.',
                publicUpdateTime == null ? trackedCase.LastModifiedDate : publicUpdateTime,
                publicStage.toLowerCase() == 'case closed' ? 'success' : 'info'
            ));
        }

        updates.add(createUpdate(
            'status-current',
            'Current Status: ' + safeText(trackedCase.Status),
            'Priority is ' + safeText(trackedCase.Priority) + '.',
            trackedCase.LastModifiedDate,
            trackedCase.IsClosed ? 'success' : 'info'
        ));

        try {
            List<CaseHistory> statusHistory = [
                SELECT Id, OldValue, NewValue, CreatedDate
                FROM CaseHistory
                WHERE CaseId = :trackedCase.Id
                AND Field = 'Status'
                ORDER BY CreatedDate DESC
                LIMIT 6
            ];

            for (CaseHistory row : statusHistory) {
                String newValue = row.NewValue == null ? 'Updated' : String.valueOf(row.NewValue);
                String oldValue = row.OldValue == null ? 'N/A' : String.valueOf(row.OldValue);
                String tone = (newValue != null && newValue.toLowerCase().contains('close'))
                    ? 'success'
                    : 'info';

                updates.add(createUpdate(
                    'history-' + row.Id,
                    'Status changed to ' + newValue,
                    'Previous status: ' + oldValue,
                    row.CreatedDate,
                    tone
                ));
            }
        } catch (Exception e) {
            // Case history can be unavailable depending on org tracking settings.
        }

        updates.add(createUpdate(
            'case-created',
            'Case created',
            'ElectroMart support received your request and generated case number ' + safeText(trackedCase.CaseNumber) + '.',
            trackedCase.CreatedDate,
            'info'
        ));

        if (trackedCase.IsClosed && trackedCase.ClosedDate != null) {
            updates.add(createUpdate(
                'case-closed',
                'Case closed',
                'The support case has been marked as resolved and closed.',
                trackedCase.ClosedDate,
                'success'
            ));
        }

        return updates;
    }

    private static TrackingUpdate createUpdate(
        String key,
        String title,
        String message,
        Datetime timestamp,
        String tone
    ) {
        TrackingUpdate updateRow = new TrackingUpdate();
        updateRow.key = key;
        updateRow.title = title;
        updateRow.message = message;
        updateRow.timestamp = timestamp;
        updateRow.tone = tone;
        return updateRow;
    }

    private static String safeText(String value) {
        return String.isBlank(value) ? 'N/A' : value;
    }
}