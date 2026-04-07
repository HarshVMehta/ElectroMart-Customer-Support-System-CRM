import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class NeedHelpCta extends NavigationMixin(LightningElement) {
    // Match your working pattern: accept a full path (including leading slash) and navigate directly
    // Default to your new page path. You can still override this in Experience Builder.
    @api webToCasePath = '/case-form';

    // Primary action for "Get Support" button: navigate directly using the provided path
    navigateToSupport() {
        // Use NavigationMixin to go to an absolute site path; this mirrors the working requestButton pattern
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: this.webToCasePath // expects leading slash, e.g., '/case-form' or '/s/case-form' based on your site routing
            }
        });
    }

    startChat() {
        if (window.embedded_svc && window.embedded_svc.liveAgentAPI) {
            window.embedded_svc.liveAgentAPI.startChat();
        } else {
            this.navigateToSupport();
        }
    }
}
