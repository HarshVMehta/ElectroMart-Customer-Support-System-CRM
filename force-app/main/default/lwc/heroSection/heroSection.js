import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class HeroSection extends NavigationMixin(LightningElement) {
    searchQuery = '';

    handleSearchInput(event) {
        this.searchQuery = event.target.value;
    }

    handleSearch() {
        if (this.searchQuery.trim()) {
            // Navigate to Support page with search query
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: {
                    pageName: 'support'
                },
                state: {
                    searchTerm: this.searchQuery
                }
            });
        }
    }

    handleKeyPress(event) {
        if (event.key === 'Enter') {
            this.handleSearch();
        }
    }

    navigateToSupport() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'support'
            }
        });
    }
}