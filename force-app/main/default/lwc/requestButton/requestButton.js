import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class RequestButton extends NavigationMixin(LightningElement) {
    /**
     * Navigate to dedicated submit-request page in Experience Cloud
     */
    navigateToRequestPage() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                // Update this path to match your site's actual page URL
                // Example: /support/s/submit-request
                url: '/case-form'
            }
        });
    }
}