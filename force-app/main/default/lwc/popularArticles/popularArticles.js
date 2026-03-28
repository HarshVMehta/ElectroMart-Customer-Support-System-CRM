import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPopularArticles from '@salesforce/apex/KnowledgeController.getPopularArticles';

export default class PopularArticles extends NavigationMixin(LightningElement) {
    articles = [];
    error;
    isLoading = true;

    // Hardcoded articles as fallback (will be replaced by actual data from Salesforce)
    defaultArticles = [
        {
            Id: '1',
            Title: 'How to Claim Warranty',
            Summary: 'Step-by-step guide to claim warranty for your ElectroMart products',
            UrlName: 'how-to-claim-warranty',
            ArticleNumber: 'KB-0001',
            ViewCount: 1250
        },
        {
            Id: '2',
            Title: 'Laptop Overheating Troubleshooting',
            Summary: 'Common solutions for laptop overheating issues and prevention tips',
            UrlName: 'laptop-overheating-troubleshooting',
            ArticleNumber: 'KB-0002',
            ViewCount: 980
        },
        {
            Id: '3',
            Title: 'Refund and Return Policy',
            Summary: 'Complete guide on ElectroMart\'s refund and return process',
            UrlName: 'refund-and-return-policy',
            ArticleNumber: 'KB-0003',
            ViewCount: 875
        },
        {
            Id: '4',
            Title: 'TV Installation Guide',
            Summary: 'Professional tips for installing and setting up your new TV',
            UrlName: 'tv-installation-guide',
            ArticleNumber: 'KB-0004',
            ViewCount: 654
        },
        {
            Id: '5',
            Title: 'Mobile Phone Screen Issues',
            Summary: 'Troubleshoot common mobile screen problems and display issues',
            UrlName: 'mobile-phone-screen-issues',
            ArticleNumber: 'KB-0005',
            ViewCount: 543
        },
        {
            Id: '6',
            Title: 'Product Registration Benefits',
            Summary: 'Learn about the benefits of registering your ElectroMart products',
            UrlName: 'product-registration-benefits',
            ArticleNumber: 'KB-0006',
            ViewCount: 432
        }
    ];

    connectedCallback() {
        // Use default articles for now
        this.articles = this.defaultArticles;
        this.isLoading = false;
    }

    // Uncomment this when Apex class is ready
    /*
    @wire(getPopularArticles, { limitCount: 6 })
    wiredArticles({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.articles = data;
            this.error = undefined;
        } else if (error) {
            this.error = error;
            this.articles = this.defaultArticles; // Fallback to default
        }
    }
    */

    handleArticleClick(event) {
        const articleId = event.currentTarget.dataset.id;
        const article = this.articles.find(art => art.Id === articleId);
        
        // Navigate to Knowledge Article detail page
        this[NavigationMixin.Navigate]({
            type: 'standard__knowledgeArticlePage',
            attributes: {
                articleType: 'Knowledge',
                urlName: article.UrlName
            }
        });
    }

    viewAllArticles() {
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: {
                pageName: 'knowledge-base'
            }
        });
    }
}