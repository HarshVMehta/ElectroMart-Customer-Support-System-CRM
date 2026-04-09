import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import CASE_NUMBER_FIELD from '@salesforce/schema/Case.CaseNumber';
import STAGE_FIELD from '@salesforce/schema/Case.Tracking_Public_Stage__c';
import UPDATE_FIELD from '@salesforce/schema/Case.Tracking_Public_Update__c';
import UPDATE_TIME_FIELD from '@salesforce/schema/Case.Tracking_Public_Update_Time__c';

const STAGES = [
    'Request Received',
    'Case Review Started',
    'Investigation in Progress',
    'Resolution in Progress',
    'Case Closed'
];

const CASE_FIELDS = [
    CASE_NUMBER_FIELD,
    STAGE_FIELD,
    UPDATE_FIELD,
    UPDATE_TIME_FIELD
];

export default class CaseTrackingConsoleUpdate extends LightningElement {
    @api recordId;

    isSaving = false;
    caseNumber;

    currentStage = STAGES[0];
    selectedStage = STAGES[0];

    updateText = '';
    originalUpdateText = '';

    lastPublishedRaw;

    @wire(getRecord, { recordId: '$recordId', fields: CASE_FIELDS })
    wiredCase({ error, data }) {
        if (data) {
            this.caseNumber = getFieldValue(data, CASE_NUMBER_FIELD);

            const stageFromRecord = getFieldValue(data, STAGE_FIELD);
            this.currentStage = STAGES.includes(stageFromRecord) ? stageFromRecord : STAGES[0];
            this.selectedStage = this.currentStage;

            const updateFromRecord = getFieldValue(data, UPDATE_FIELD) || '';
            this.originalUpdateText = updateFromRecord;
            this.updateText = updateFromRecord;

            this.lastPublishedRaw = getFieldValue(data, UPDATE_TIME_FIELD);
            return;
        }

        if (error) {
            this.showToast('Error', this.resolveError(error), 'error');
        }
    }

    renderedCallback() {
        const updateInput = this.template.querySelector('[data-field="publicUpdate"]');
        if (updateInput && updateInput.value !== this.updateText) {
            updateInput.value = this.updateText;
        }
    }

    get stageItems() {
        const selectedIndex = STAGES.indexOf(this.selectedStage);

        return STAGES.map((stageLabel, index) => {
            const isCurrent = index === selectedIndex;
            const isComplete = index < selectedIndex;
            const isFinal = index === STAGES.length - 1;

            let chipClass = 'stage-chip';
            if (isCurrent) {
                chipClass += ' current';
            } else if (isComplete) {
                chipClass += ' done';
            }

            let connectorClass = 'stage-connector';
            if (!isFinal && (isComplete || isCurrent)) {
                connectorClass += ' active';
            }

            return {
                key: `stage-${index}`,
                label: stageLabel,
                index: index + 1,
                isFinal,
                chipClass,
                connectorClass,
                ariaPressed: isCurrent ? 'true' : 'false'
            };
        });
    }

    get hasUnsavedChanges() {
        return this.selectedStage !== this.currentStage
            || (this.updateText || '') !== (this.originalUpdateText || '');
    }

    get publishButtonLabel() {
        return this.isSaving ? 'Publishing...' : 'Publish Update';
    }

    get disablePublish() {
        return this.isSaving || !this.recordId || !this.hasUnsavedChanges;
    }

    get disableReset() {
        return this.isSaving || !this.hasUnsavedChanges;
    }

    get formattedLastPublished() {
        if (!this.lastPublishedRaw) {
            return 'Not published yet';
        }

        return this.formatDate(this.lastPublishedRaw);
    }

    get helperSummary() {
        return `Current stage: ${this.selectedStage}`;
    }

    handleSelectStage(event) {
        this.selectedStage = event.currentTarget.dataset.stage;
    }

    handleUpdateTextChange(event) {
        this.updateText = event.target.value || '';
    }

    handleReset() {
        this.selectedStage = this.currentStage;
        this.updateText = this.originalUpdateText;
    }

    async handlePublishUpdate() {
        if (this.disablePublish) {
            return;
        }

        this.isSaving = true;

        try {
            const trimmedUpdate = (this.updateText || '').trim();
            const nowIso = new Date().toISOString();

            const fields = {
                Id: this.recordId,
                [STAGE_FIELD.fieldApiName]: this.selectedStage,
                [UPDATE_FIELD.fieldApiName]: trimmedUpdate,
                [UPDATE_TIME_FIELD.fieldApiName]: nowIso
            };

            await updateRecord({ fields });

            this.currentStage = this.selectedStage;
            this.originalUpdateText = trimmedUpdate;
            this.updateText = trimmedUpdate;
            this.lastPublishedRaw = nowIso;

            this.showToast('Success', 'Customer tracking update published.', 'success');
        } catch (error) {
            this.showToast('Update Failed', this.resolveError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    formatDate(value) {
        const dateValue = new Date(value);
        if (Number.isNaN(dateValue.getTime())) {
            return 'Not available';
        }

        return new Intl.DateTimeFormat('en-US', {
            month: 'short',
            day: '2-digit',
            year: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        }).format(dateValue);
    }

    resolveError(error) {
        if (error && error.body && Array.isArray(error.body) && error.body.length > 0) {
            return error.body.map((item) => item.message).join(', ');
        }

        if (error && error.body && error.body.message) {
            return error.body.message;
        }

        if (error && error.message) {
            return error.message;
        }

        return 'Something went wrong while updating the case tracking details.';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}
