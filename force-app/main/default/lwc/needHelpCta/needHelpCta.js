import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class NeedHelpCta extends NavigationMixin(LightningElement) {
    
    navigateToSupport() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'support'
            }
        });
    }

    startChat() {
        // This will trigger the chat widget
        // You can integrate with Salesforce Chat or custom chat solution
        if (window.embedded_svc) {
            window.embedded_svc.liveAgentAPI.startChat();
        } else {
            // Fallback: Navigate to support page
            this.navigateToSupport();
        }
    }
}