import { LightningElement } from 'lwc';
import createCase from '@salesforce/apex/WebToCaseController.createCase';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class WebToCaseForm extends NavigationMixin(LightningElement) {
    // Form Fields
    name = '';
    email = '';
    subject = '';
    description = '';
    product = '';
    issueCategory = '';

    // State Management
    isLoading = false;
    // errors map drives inline messages; keys: name, email, subject, description, product, issueCategory
    errors = {};
    // Inline success banner state
    showInlineSuccess = false;
    successMessage = '';

    // Validation Patterns
    emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

    /**
     * Handle Name Input Change (REAL-TIME)
     */
    handleName(e) {
        this.name = e.target.value;
        // Validate immediately as user types
        this.validateName();
    }

    /**
     * Handle Email Input Change (REAL-TIME)
     */
    handleEmail(e) {
        this.email = e.target.value;
        this.validateEmail();
    }

    /**
     * Handle Subject Input Change (REAL-TIME)
     */
    handleSubject(e) {
        this.subject = e.target.value;
        this.validateSubject();
    }

    /**
     * Handle Description Input Change (REAL-TIME)
     */
    handleDescription(e) {
        this.description = e.target.value;
        this.validateDescription();
    }

    /**
     * Handle Product Selection Change (IMMEDIATE)
     */
    handleProduct(e) {
        this.product = e.target.value;
        this.validateProduct();
    }

    /**
     * Handle Issue Category Selection Change (IMMEDIATE)
     */
    handleIssue(e) {
        this.issueCategory = e.target.value;
        this.validateIssueCategory();
    }

    /**
     * Navigate to previous browser page with fallback to Support page.
     */
    handleGoBack() {
        if (typeof window !== 'undefined' && window.history && window.history.length > 1) {
            window.history.back();
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'support'
            }
        });
    }

    /**
     * Quick action to open knowledge-base page.
     */
    navigateToKnowledgeBase() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'knowledge-base'
            }
        });
    }

    /**
     * Keep non-bindable native fields (select/textarea) synced after rerenders.
     */
    renderedCallback() {
        this.syncFieldValue('product', this.product);
        this.syncFieldValue('issueCategory', this.issueCategory);
        this.syncFieldValue('description', this.description);
    }

    syncFieldValue(fieldName, value) {
        const field = this.template.querySelector(`[data-field="${fieldName}"]`);
        const normalized = value || '';
        if (field && field.value !== normalized) {
            field.value = normalized;
        }
    }

    /**
     * Validate Name Field
     * Rules:
     * - Required
     * - At least 2 characters
     * - Max 100 characters
     * - Only letters, spaces, hyphens, apostrophes (no digits or emojis)
     */
    validateName() {
        const v = (this.name || '').trim();
        
        if (!v) {
            this.errors = { ...this.errors, name: 'Contact name is required' };
            return false;
        }
        
        if (v.length < 2) {
            this.errors = { ...this.errors, name: 'Name must be at least 2 characters' };
            return false;
        }
        
        if (v.length > 100) {
            this.errors = { ...this.errors, name: 'Name cannot exceed 100 characters' };
            return false;
        }
        
        // Only letters, spaces, hyphens, apostrophes
        if (!/^[a-zA-Z\s\-']+$/.test(v)) {
            this.errors = { ...this.errors, name: 'Name can only contain letters, spaces, hyphens, and apostrophes' };
            return false;
        }
        
        // Clear error if valid
        const { name, ...rest } = this.errors;
        this.errors = rest;
        return true;
    }

    /**
     * Validate Email Field
     * Rules:
     * - Required
     * - Valid email format (user@example.com)
     * - Max 100 characters
     */
    validateEmail() {
        const v = (this.email || '').trim();
        
        if (!v) {
            this.errors = { ...this.errors, email: 'Email address is required' };
            return false;
        }
        
        if (!this.emailPattern.test(v)) {
            this.errors = { ...this.errors, email: 'Please enter a valid email (e.g., user@example.com)' };
            return false;
        }
        
        if (v.length > 100) {
            this.errors = { ...this.errors, email: 'Email cannot exceed 100 characters' };
            return false;
        }
        
        // Clear error if valid
        const { email, ...rest } = this.errors;
        this.errors = rest;
        return true;
    }

    /**
     * Validate Subject Field
     * Rules:
     * - Required
     * - Min 5 characters
     * - Max 100 characters
     */
    validateSubject() {
        const v = (this.subject || '').trim();
        
        if (!v) {
            this.errors = { ...this.errors, subject: 'Subject is required' };
            return false;
        }
        
        if (v.length < 5) {
            this.errors = { ...this.errors, subject: 'Subject must be at least 5 characters' };
            return false;
        }
        
        if (v.length > 100) {
            this.errors = { ...this.errors, subject: 'Subject cannot exceed 100 characters' };
            return false;
        }
        
        // Clear error if valid
        const { subject, ...rest } = this.errors;
        this.errors = rest;
        return true;
    }

    /**
     * Validate Description Field
     * Rules:
     * - Required
     * - Min 10 characters
     * - Max 2000 characters
     */
    validateDescription() {
        const v = (this.description || '').trim();
        
        if (!v) {
            this.errors = { ...this.errors, description: 'Description is required' };
            return false;
        }
        
        if (v.length < 10) {
            this.errors = { ...this.errors, description: 'Description must be at least 10 characters' };
            return false;
        }
        
        if (v.length > 2000) {
            this.errors = { ...this.errors, description: 'Description cannot exceed 2000 characters' };
            return false;
        }
        
        // Clear error if valid
        const { description, ...rest } = this.errors;
        this.errors = rest;
        return true;
    }

    /**
     * Validate Product Selection
     * Rules:
     * - Required (must select non-empty option)
     */
    validateProduct() {
        const v = (this.product || '').trim();
        
        if (!v) {
            this.errors = { ...this.errors, product: 'Please select a product category' };
            return false;
        }
        
        // Clear error if valid
        const { product, ...rest } = this.errors;
        this.errors = rest;
        return true;
    }

    /**
     * Validate Issue Category Selection
     * Rules:
     * - Required (must select non-empty option)
     */
    validateIssueCategory() {
        const v = (this.issueCategory || '').trim();
        
        if (!v) {
            this.errors = { ...this.errors, issueCategory: 'Please select an issue category' };
            return false;
        }
        
        // Clear error if valid
        const { issueCategory, ...rest } = this.errors;
        this.errors = rest;
        return true;
    }

    /**
     * Validate All Fields at Once
     * Returns true only if ALL fields are valid
     */
    validateAllFields() {
        const isNameValid = this.validateName();
        const isEmailValid = this.validateEmail();
        const isSubjectValid = this.validateSubject();
        const isDescriptionValid = this.validateDescription();
        const isProductValid = this.validateProduct();
        const isIssueValid = this.validateIssueCategory();

        return isNameValid && isEmailValid && isSubjectValid && 
               isDescriptionValid && isProductValid && isIssueValid;
    }

    /**
     * Check if form has ANY errors
     */
    get hasErrors() {
        return Object.keys(this.errors).length > 0;
    }

    /**
     * Computed getters for character counts
     */
    get subjectLength() {
        return this.subject ? this.subject.length : 0;
    }

    get descriptionLength() {
        return this.description ? this.description.length : 0;
    }

    /**
     * Check if subject is approaching limit
     */
    get subjectNearLimit() {
        return this.subjectLength > 80;
    }

    /**
     * Check if description is approaching limit
     */
    get descriptionNearLimit() {
        return this.descriptionLength > 1800;
    }

    /**
     * Computed CSS classes for error styling
     */
    get nameInputClass() {
        return this.errors.name ? 'form-input error' : 'form-input';
    }

    get emailInputClass() {
        return this.errors.email ? 'form-input error' : 'form-input';
    }

    get subjectInputClass() {
        return this.errors.subject ? 'form-input error' : 'form-input';
    }

    get productSelectClass() {
        return this.errors.product ? 'form-select error' : 'form-select';
    }

    get issueCategorySelectClass() {
        return this.errors.issueCategory ? 'form-select error' : 'form-select';
    }

    get descriptionTextareaClass() {
        return this.errors.description ? 'form-textarea error' : 'form-textarea';
    }

    get subjectCharCountClass() {
        let classes = 'char-count';
        if (this.subjectNearLimit) classes += ' warning';
        return classes;
    }

    get descriptionCharCountClass() {
        let classes = 'char-count';
        if (this.descriptionNearLimit) classes += ' warning';
        return classes;
    }

    /**
     * Handle Form Submission
     * BLOCKS submission if any validation fails
     */
    handleSubmit() {
        console.log('[webToCaseForm] handleSubmit clicked');

        // Validate ALL fields
        const valid = this.validateAllFields();
        
        if (!valid) {
            // Show toast with error
            this.showToast(
                'Validation Error', 
                'Please fix the errors highlighted in red before submitting', 
                'error'
            );
            console.warn('[webToCaseForm] Validation failed. Errors:', JSON.parse(JSON.stringify(this.errors)));
            
            // Scroll to first error field
            this.scrollToFirstError();
            return;
        }

        // All valid - proceed with submission
        this.isLoading = true;

        const payload = {
            name: this.name.trim(),
            email: this.email.trim(),
            subject: this.subject.trim(),
            description: this.description.trim(),
            product: this.product,
            issueType: this.issueCategory
        };
        
        console.log('[webToCaseForm] Calling Apex.createCase with payload:', JSON.parse(JSON.stringify(payload)));

        createCase(payload)
            .then(result => {
                console.log('[webToCaseForm] Apex result:', result);

                // Inline success banner (visible on page)
                this.successMessage = `Your support request has been submitted successfully. Case ID: ${result}`;
                this.showInlineSuccess = true;

                // Toast (still keep the toast for platform consistency)
                this.showToast(
                    'Success!',
                    this.successMessage,
                    'success'
                );

                // Clear form fields
                this.resetForm();

                // Auto-hide banner after 6 seconds
                window.clearTimeout(this._successTimer);
                this._successTimer = window.setTimeout(() => {
                    this.showInlineSuccess = false;
                    this.successMessage = '';
                }, 6000);

                this.isLoading = false;
            })
            .catch(error => {
                let errorMessage = 'Error creating case. Please try again.';
                if (error && error.body && error.body.message) {
                    errorMessage = error.body.message;
                } else if (error && error.body && error.body.exceptionMessage) {
                    errorMessage = error.body.exceptionMessage;
                }
                console.error('[webToCaseForm] Apex error:', JSON.parse(JSON.stringify(error)));
                this.showToast('Error', errorMessage, 'error');
                this.isLoading = false;
            });
    }

    disconnectedCallback() {
        if (typeof window !== 'undefined') {
            window.clearTimeout(this._successTimer);
        }
    }

    /**
     * Scroll to first error field
     */
    scrollToFirstError() {
        const errorFields = this.template.querySelectorAll('.form-input.error, .form-textarea.error, .form-select.error');
        if (errorFields.length > 0) {
            errorFields[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
            errorFields[0].focus();
        }
    }

    /**
     * Show Toast Message
     */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    /**
     * Clear Form Fields and Errors
     * Also clears the native input/select/textarea values visually.
     */
    resetForm() {
        // Reset tracked state
        this.name = '';
        this.email = '';
        this.subject = '';
        this.description = '';
        this.product = '';
        this.issueCategory = '';
        this.errors = {};
        // Do not clear the success banner here; caller controls it (so success message stays visible)

        // Clear DOM values so UI reflects the reset instantly
        ['name', 'email', 'subject', 'description', 'product', 'issueCategory'].forEach((fieldName) => {
            const field = this.template.querySelector(`[data-field="${fieldName}"]`);
            if (field) {
                field.value = '';
            }
        });

        // Remove any error classes from inputs/selects/textarea
        this.template.querySelectorAll('.error').forEach(el => el.classList.remove('error'));
    }

    /**
     * Handle Reset Button Click
     */
    handleReset() {
        this.resetForm();
        this.showToast('Info', 'Form cleared successfully', 'info');
    }
}