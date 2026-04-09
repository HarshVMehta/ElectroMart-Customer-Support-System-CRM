import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import requestTrackingOtp from '@salesforce/apex/CaseTrackingController.requestTrackingOtp';
import verifyTrackingOtp from '@salesforce/apex/CaseTrackingController.verifyTrackingOtp';

const OTP_LENGTH = 6;
const DEFAULT_RESEND_COOLDOWN = 45;

export default class CaseTrackingModule extends LightningElement {
    caseReference = '';
    otpCode = '';

    activeStep = 'lookup';
    maskedEmail = '';
    tracking = null;

    isLoading = false;
    loadingAction = '';

    resendCountdown = 0;

    toastVisible = false;
    toastTitle = '';
    toastMessage = '';
    toastVariant = 'info';

    _resendTimer;
    _toastTimer;

    disconnectedCallback() {
        this.clearResendCountdown();
        this.clearToastTimer();
    }

    handleCaseReferenceInput(event) {
        this.caseReference = (event.target.value || '').trim();
    }

    handleOtpInput(event) {
        const digitsOnly = (event.target.value || '').replace(/\D/g, '').slice(0, OTP_LENGTH);
        this.otpCode = digitsOnly;

        if (event.target.value !== digitsOnly) {
            event.target.value = digitsOnly;
        }
    }

    async handleSendOtp() {
        await this.requestOtp(false);
    }

    async handleResendOtp() {
        if (this.isResendDisabled) {
            return;
        }

        await this.requestOtp(true);
    }

    async requestOtp(isResend) {
        if (!this.caseReference) {
            this.showToast('Missing Case Reference', 'Please enter a valid Case Number or Case ID.', 'error');
            return;
        }

        this.isLoading = true;
        this.loadingAction = 'request';

        try {
            const response = await requestTrackingOtp({
                caseReference: this.caseReference
            });

            if (!response || response.success !== true) {
                throw new Error((response && response.message) || 'Unable to send OTP right now.');
            }

            this.activeStep = 'verify';
            this.maskedEmail = response.maskedEmail || '';
            this.otpCode = '';
            this.tracking = null;

            this.startResendCountdown(response.resendAvailableInSeconds || DEFAULT_RESEND_COOLDOWN);

            this.showToast(
                isResend ? 'OTP Resent' : 'OTP Sent',
                response.message || 'Check your email for the one-time password.',
                'success'
            );
        } catch (error) {
            this.showToast('Unable to Send OTP', this.resolveError(error), 'error');
        } finally {
            this.isLoading = false;
            this.loadingAction = '';
        }
    }

    async handleVerifyOtp() {
        if (this.otpCode.length !== OTP_LENGTH) {
            this.showToast('Invalid OTP', `Enter a valid ${OTP_LENGTH}-digit OTP.`, 'error');
            return;
        }

        this.isLoading = true;
        this.loadingAction = 'verify';

        try {
            const response = await verifyTrackingOtp({
                caseReference: this.caseReference,
                otpCode: this.otpCode
            });

            if (!response || response.success !== true || !response.tracking) {
                throw new Error((response && response.message) || 'Unable to verify OTP.');
            }

            this.tracking = response.tracking;
            this.activeStep = 'results';

            this.showToast('Verified', 'Case updates loaded successfully.', 'success');
        } catch (error) {
            this.showToast('OTP Verification Failed', this.resolveError(error), 'error');
        } finally {
            this.isLoading = false;
            this.loadingAction = '';
        }
    }

    handleTrackAnother() {
        this.caseReference = '';
        this.otpCode = '';
        this.activeStep = 'lookup';
        this.maskedEmail = '';
        this.tracking = null;
        this.clearResendCountdown();
    }

    get showOtpPanel() {
        return this.activeStep === 'verify';
    }

    get showResults() {
        return this.activeStep === 'results' && this.tracking;
    }

    get requestButtonLabel() {
        if (this.isLoading && this.loadingAction === 'request') {
            return 'Sending OTP...';
        }

        return 'Send OTP';
    }

    get verifyButtonLabel() {
        if (this.isLoading && this.loadingAction === 'verify') {
            return 'Verifying...';
        }

        return 'Verify and View Updates';
    }

    get isRequestDisabled() {
        return this.isLoading || !this.caseReference;
    }

    get isVerifyDisabled() {
        return this.isLoading || this.otpCode.length !== OTP_LENGTH;
    }

    get isResendDisabled() {
        return this.isLoading || this.resendCountdown > 0;
    }

    get resendLabel() {
        if (this.resendCountdown > 0) {
            return `Resend OTP in ${this.resendCountdown}s`;
        }

        return 'Resend OTP';
    }

    get lookupStepClass() {
        return this.computeStepClass('lookup');
    }

    get verifyStepClass() {
        return this.computeStepClass('verify');
    }

    get resultStepClass() {
        return this.computeStepClass('results');
    }

    computeStepClass(stepName) {
        if (this.activeStep === stepName) {
            return 'step-pill current';
        }

        const order = {
            lookup: 1,
            verify: 2,
            results: 3
        };

        if (order[this.activeStep] > order[stepName]) {
            return 'step-pill done';
        }

        return 'step-pill';
    }

    get stageItems() {
        const rawStages = (this.tracking && this.tracking.stages) || [];

        return rawStages.map((stage, index) => {
            const isLast = index === rawStages.length - 1;
            let nodeClass = 'stage-node pending';

            if (stage.completed) {
                nodeClass = 'stage-node done';
            } else if (stage.current) {
                nodeClass = 'stage-node current';
            }

            let connectorClass = 'stage-connector';
            if (!isLast && (stage.completed || stage.current)) {
                connectorClass += ' active';
            }

            return {
                ...stage,
                isLast,
                nodeClass,
                connectorClass,
                formattedTimestamp: this.formatDate(stage.timestamp)
            };
        });
    }

    get updateItems() {
        const rawUpdates = (this.tracking && this.tracking.updates) || [];

        return rawUpdates.filter((updateRow) => updateRow && updateRow.key !== 'public-update').map((updateRow, index) => {
            const tone = updateRow.tone || 'info';
            return {
                ...updateRow,
                key: updateRow.key || `update-${index}`,
                cardClass: `update-item ${tone}`,
                formattedTimestamp: this.formatDate(updateRow.timestamp)
            };
        });
    }

    get hasUpdates() {
        return this.updateItems.length > 0;
    }

    get effectiveStageLabel() {
        if (this.tracking && this.tracking.publicStage) {
            return this.tracking.publicStage;
        }

        if (this.tracking && this.tracking.status) {
            return this.tracking.status;
        }

        return 'N/A';
    }

    get hasPublicUpdate() {
        return Boolean(this.tracking && this.tracking.publicUpdate);
    }

    get publicUpdateText() {
        return (this.tracking && this.tracking.publicUpdate) || '';
    }

    get formattedPublicUpdateTime() {
        const sourceTime = (this.tracking && this.tracking.publicUpdateTime)
            || (this.tracking && this.tracking.lastUpdatedDate);
        return this.formatDate(sourceTime);
    }

    get formattedCreatedDate() {
        return this.formatDate(this.tracking && this.tracking.createdDate);
    }

    get formattedLastUpdatedDate() {
        return this.formatDate(this.tracking && this.tracking.lastUpdatedDate);
    }

    get caseStatusPillClass() {
        const status = this.effectiveStageLabel.toLowerCase();
        if (status.includes('close') || status.includes('resolve')) {
            return 'status-pill closed';
        }

        if (status.includes('pending') || status.includes('wait')) {
            return 'status-pill pending';
        }

        return 'status-pill active';
    }

    get toastClass() {
        return `floating-toast ${this.toastVariant}`;
    }

    get toastSymbol() {
        if (this.toastVariant === 'success') {
            return '✓';
        }

        if (this.toastVariant === 'error') {
            return '!';
        }

        if (this.toastVariant === 'warning') {
            return '!';
        }

        return 'i';
    }

    closeToast() {
        this.toastVisible = false;
    }

    formatDate(value) {
        if (!value) {
            return 'Pending';
        }

        const asDate = new Date(value);
        if (Number.isNaN(asDate.getTime())) {
            return 'Pending';
        }

        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        }).format(asDate);
    }

    startResendCountdown(seconds) {
        this.clearResendCountdown();
        this.resendCountdown = Math.max(0, Number(seconds) || DEFAULT_RESEND_COOLDOWN);

        if (this.resendCountdown <= 0 || typeof window === 'undefined') {
            return;
        }

        this._resendTimer = window.setInterval(() => {
            this.resendCountdown -= 1;
            if (this.resendCountdown <= 0) {
                this.clearResendCountdown();
            }
        }, 1000);
    }

    clearResendCountdown() {
        if (typeof window !== 'undefined' && this._resendTimer) {
            window.clearInterval(this._resendTimer);
        }
        this._resendTimer = null;
        this.resendCountdown = 0;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );

        this.toastTitle = title;
        this.toastMessage = message;
        this.toastVariant = variant || 'info';
        this.toastVisible = true;

        this.clearToastTimer();
        if (typeof window !== 'undefined') {
            this._toastTimer = window.setTimeout(() => {
                this.toastVisible = false;
            }, 5000);
        }
    }

    clearToastTimer() {
        if (typeof window !== 'undefined' && this._toastTimer) {
            window.clearTimeout(this._toastTimer);
        }
        this._toastTimer = null;
    }

    resolveError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }

        if (error && error.message) {
            return error.message;
        }

        return 'Something went wrong. Please try again.';
    }
}
