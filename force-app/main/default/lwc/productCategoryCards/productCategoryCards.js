import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class ProductCategoryCards extends NavigationMixin(LightningElement) {
    categories = [
        {
            id: '1',
            name: 'Mobiles',
            icon: 'custom:custom63',
            emoji: '📱',
            description: 'Smartphones & Accessories',
            color: '#4CAF50',
            articles: 24
        },
        {
            id: '2',
            name: 'Laptops',
            icon: 'custom:custom85',
            emoji: '💻',
            description: 'Notebooks & Computers',
            color: '#2196F3',
            articles: 32
        },
        {
            id: '3',
            name: 'TVs',
            icon: 'custom:custom108',
            emoji: '📺',
            description: 'Televisions & Home Theater',
            color: '#FF9800',
            articles: 18
        },
        {
            id: '4',
            name: 'Appliances',
            icon: 'custom:custom14',
            emoji: '🏠',
            description: 'Home Appliances',
            color: '#9C27B0',
            articles: 28
        },
        {
            id: '5',
            name: 'Warranty',
            icon: 'standard:return_order',
            emoji: '🛡️',
            description: 'Warranty & Returns',
            color: '#F44336',
            articles: 15
        }
    ];

    handleCategoryClick(event) {
        const categoryName = event.currentTarget.dataset.category;
        
        // Navigate to support page with category filter
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'support'
            },
            state: {
                category: categoryName
            }
        });
    }
}