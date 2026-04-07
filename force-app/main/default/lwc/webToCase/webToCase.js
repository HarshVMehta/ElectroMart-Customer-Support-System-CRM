import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class WebToCase extends NavigationMixin(LightningElement) {
    isSubmitting = false;
    showSuccess = false;
    showError = false;
    errorMessage = '';
    caseNumber = '';
    
    // Salesforce Web-to-Case endpoint
    SALESFORCE_ENDPOINT = 'https://webto.salesforce.com/servlet/servlet.WebToCase?encoding=UTF-8&orgId=00DgK00000Kt6in';

    /**
     * Navigate back to support page
     */
    navigateBack() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                // Update if your support page has a different URL
                url: '/s/support'
            }
        });
    }

    /**
     * Navigate to My Cases page
     */
    navigateToMyCases() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                // Update if your my-cases page has a different URL
                url: '/s/my-cases'
            }
        });
    }

    /**
     * Handle form submission
     */
    handleSubmit(event) {
        event.preventDefault();
        
        if (!this.validateForm()) {
            return;
        }

        this.isSubmitting = true;
        this.showError = false;

        const formElement = this.template.querySelector('form');
        const formData = new FormData(formElement);

        this.submitToSalesforce(formData);
    }

    validateForm() {
        const allValid = [...this.template.querySelectorAll('input, select, textarea')]
            .filter(field => field.required)
            .reduce((validSoFar, inputField) => {
                if (!inputField.checkValidity()) {
                    inputField.reportValidity();
                    return false;
                }
                return validSoFar;
            }, true);

        if (!allValid) {
            this.showError = true;
            this.errorMessage = 'Please fill in all required fields correctly.';
            this.scrollToTop();
        }

        return allValid;
    }

    async submitToSalesforce(formData) {
        try {
            const iframe = document.createElement('iframe');
            iframe.name = 'salesforceWebToCase';
            iframe.style.display = 'none';
            document.body.appendChild(iframe);

            const form = document.createElement('form');
            form.action = this.SALESFORCE_ENDPOINT;
            form.method = 'POST';
            form.target = 'salesforceWebToCase';

            for (let [key, value] of formData.entries()) {
                const input = document.createElement('input');
                input.type = 'hidden';
                input.name = key;
                input.value = value;
                form.appendChild(input);
            }

            document.body.appendChild(form);
            form.submit();

            setTimeout(() => {
                document.body.removeChild(form);
                document.body.removeChild(iframe);
            }, 1000);

            this.handleSuccess();
        } catch (error) {
            this.handleError(error);
        }
    }

    handleSuccess() {
        this.isSubmitting = false;
        this.showSuccess = true;
        this.showError = false;
        this.caseNumber = this.generateReferenceNumber();

        this.dispatchEvent(new CustomEvent('casecreated', {
            detail: {
                success: true,
                caseNumber: this.caseNumber
            }
        }));

        this.scrollToTop();
    }

    handleError(error) {
        this.isSubmitting = false;
        this.showSuccess = false;
        this.showError = true;
        this.errorMessage = 'An error occurred while submitting your request. Please try again or contact support directly.';

        this.dispatchEvent(new CustomEvent('caseerror', {
            detail: {
                success: false,
                error: error.message
            }
        }));

        this.scrollToTop();
    }

    handleCancel() {
        const hasData = this.checkFormHasData();
        
        if (hasData) {
            const confirmLeave = confirm('Are you sure you want to cancel? Your information will not be saved.');
            if (!confirmLeave) {
                return;
            }
        }

        this.navigateBack();
    }

    checkFormHasData() {
        const inputs = this.template.querySelectorAll('input:not([type="hidden"]), select, textarea');
        return Array.from(inputs).some(field => field.value && field.value.trim() !== '');
    }

    generateReferenceNumber() {
        const now = new Date();
        const year = now.getFullYear();
        const month = String(now.getMonth() + 1).padStart(2, '0');
        const day = String(now.getDate()).padStart(2, '0');
        const hours = String(now.getHours()).padStart(2, '0');
        const minutes = String(now.getMinutes()).padStart(2, '0');
        const seconds = String(now.getSeconds()).padStart(2, '0');
        const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
        
        return `${year}${month}${day}-${hours}${minutes}${seconds}-${random}`;
    }

    scrollToTop() {
        window.scrollTo({ top: 0, behavior: 'smooth' });
    }
}