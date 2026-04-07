import { LightningElement } from 'lwc';
import getArticlesByCategory from '@salesforce/apex/KnowledgeController.getArticlesByCategory';
import getArticleDetails from '@salesforce/apex/KnowledgeController.getArticleDetails';
import getCategoryArticleCounts from '@salesforce/apex/KnowledgeController.getCategoryArticleCounts';
import getArticleViewCounts from '@salesforce/apex/KnowledgeController.getArticleViewCounts';
import recordArticleView from '@salesforce/apex/KnowledgeController.recordArticleView';

const CATEGORY_RESULTS_LIMIT = 8;

export default class ProductCategoryCards extends LightningElement {
    categories = [
        {
            id: '1',
            name: 'Mobiles',
            categoryValue: 'Mobile',
            icon: 'custom:custom63',
            emoji: '📱',
            description: 'Smartphones & Accessories',
            color: '#4CAF50',
            articles: 24
        },
        {
            id: '2',
            name: 'Laptops',
            categoryValue: 'Laptop',
            icon: 'custom:custom85',
            emoji: '💻',
            description: 'Notebooks & Computers',
            color: '#2196F3',
            articles: 32
        },
        {
            id: '3',
            name: 'TVs',
            categoryValue: 'Television',
            icon: 'custom:custom108',
            emoji: '📺',
            description: 'Televisions & Home Theater',
            color: '#FF9800',
            articles: 18
        },
        {
            id: '4',
            name: 'Appliances',
            categoryValue: 'Home Appliance',
            icon: 'custom:custom14',
            emoji: '🏠',
            description: 'Home Appliances',
            color: '#9C27B0',
            articles: 28
        },
        {
            id: '5',
            name: 'Warranty',
            categoryValue: 'Warranty',
            icon: 'standard:return_order',
            emoji: '🛡️',
            description: 'Warranty & Returns',
            color: '#F44336',
            articles: 15
        }
    ];

    selectedCategoryId = '';
    selectedCategoryName = '';

    categoryArticles = [];
    isLoadingCategoryArticles = false;
    categoryError = '';

    isArticleModalOpen = false;
    selectedArticle = null;
    isArticleDetailLoading = false;
    articleDetailError = '';

    isResultsPanelOpen = false;
    shouldFocusResultsPanel = false;

    connectedCallback() {
        this.loadCategoryCounts();
    }

    renderedCallback() {
        if (!this.shouldFocusResultsPanel || !this.showCategoryArticlesSection) {
            return;
        }

        const heading = this.template.querySelector('.results-title-anchor');
        if (heading) {
            heading.focus();
            this.shouldFocusResultsPanel = false;
        }
    }

    get displayCategories() {
        return this.categories.map((category) => {
            const isActive = category.id === this.selectedCategoryId;
            const isLoadingActive = isActive && this.isLoadingCategoryArticles;

            return {
                ...category,
                cardClass: isActive
                    ? 'category-card active'
                    : 'category-card',
                viewLinkClass: isLoadingActive ? 'view-link loading' : 'view-link',
                actionLabel: isLoadingActive
                    ? 'Loading articles'
                    : isActive
                        ? 'Viewing now'
                        : 'View articles',
                showArrow: !isLoadingActive
            };
        });
    }

    get showCategoryArticlesSection() {
        return this.isResultsPanelOpen && Boolean(this.selectedCategoryId);
    }

    get hasCategoryArticles() {
        return this.categoryArticles.length > 0;
    }

    get hasCategoryError() {
        return Boolean(this.categoryError);
    }

    get noCategoryArticlesFound() {
        return this.showCategoryArticlesSection
            && !this.isLoadingCategoryArticles
            && !this.hasCategoryError
            && !this.hasCategoryArticles;
    }

    get selectedCategoryHeading() {
        if (!this.selectedCategoryName) {
            return 'Category Articles';
        }

        return `${this.selectedCategoryName} Articles`;
    }

    get sectionSubtitle() {
        if (!this.selectedCategoryName) {
            return '';
        }

        return `Showing real-time knowledge articles for ${this.selectedCategoryName}`;
    }

    get categoryResultCountLabel() {
        const count = this.categoryArticles.length;
        return `${count} article${count === 1 ? '' : 's'} found`;
    }

    get resultPanelAriaLabel() {
        if (!this.selectedCategoryName) {
            return 'Category article results';
        }

        return `${this.selectedCategoryName} article results`;
    }

    get selectedArticleSummary() {
        if (!this.selectedArticle) {
            return '';
        }

        return this.selectedArticle.safeSummary || this.selectedArticle.Summary || 'No detailed summary is available.';
    }

    get selectedArticleBody() {
        if (!this.selectedArticle) {
            return '';
        }

        if (this.selectedArticle.bodyContent && this.selectedArticle.bodyContent.trim()) {
            return this.selectedArticle.bodyContent;
        }

        return this.selectedArticleSummary;
    }

    get selectedArticleNumber() {
        if (!this.selectedArticle || !this.selectedArticle.ArticleNumber) {
            return 'N/A';
        }

        return this.selectedArticle.ArticleNumber;
    }

    get selectedArticleViews() {
        if (!this.selectedArticle) {
            return 0;
        }

        if (typeof this.selectedArticle.ViewCount === 'number') {
            return this.selectedArticle.ViewCount;
        }

        if (!this.selectedArticle.ArticleTotalViewCount) {
            return 0;
        }

        return this.selectedArticle.ArticleTotalViewCount;
    }

    get hasArticleDetailError() {
        return Boolean(this.articleDetailError);
    }

    async handleCategoryClick(event) {
        const selectedCategoryId = event.currentTarget.dataset.id;
        const selectedCategory = this.categories.find((category) => category.id === selectedCategoryId);

        if (!selectedCategory) {
            return;
        }

        this.selectedCategoryId = selectedCategory.id;
        this.selectedCategoryName = selectedCategory.name;
        this.isResultsPanelOpen = true;
        this.shouldFocusResultsPanel = true;
        this.categoryError = '';
        this.categoryArticles = [];
        this.isLoadingCategoryArticles = true;

        try {
            const results = await getArticlesByCategory({
                category: selectedCategory.categoryValue,
                limitCount: CATEGORY_RESULTS_LIMIT
            });

            const normalizedResults = (results || []).map((article) => {
                return {
                    ...article,
                    safeSummary: article.Summary || 'No summary available yet.',
                    ViewCount: 0
                };
            });

            this.categoryArticles = await this.attachCategoryArticleViewCounts(normalizedResults);
        } catch (error) {
            this.categoryError = this.extractErrorMessage(error);
            this.categoryArticles = [];
        } finally {
            this.isLoadingCategoryArticles = false;
        }
    }

    async handleArticleClick(event) {
        const articleId = event.currentTarget.dataset.id;
        const selected = this.categoryArticles.find((article) => article.Id === articleId);

        if (!selected) {
            return;
        }

        this.selectedArticle = {
            ...selected,
            ViewCount: this.normalizeViewCount(selected.ViewCount),
            bodyContent: ''
        };
        this.isArticleModalOpen = true;
        this.isArticleDetailLoading = true;
        this.articleDetailError = '';

        this.recordAndApplyViewCount(selected.Id);

        try {
            const details = await getArticleDetails({ articleVersionId: selected.Id });

            if (details) {
                this.selectedArticle = {
                    ...this.selectedArticle,
                    Title: details.title || this.selectedArticle.Title,
                    Summary: details.summary || this.selectedArticle.Summary,
                    safeSummary: details.summary || this.selectedArticle.safeSummary,
                    UrlName: details.urlName || this.selectedArticle.UrlName,
                    ArticleNumber: details.articleNumber || this.selectedArticle.ArticleNumber,
                    ArticleTotalViewCount: details.articleTotalViewCount !== null && details.articleTotalViewCount !== undefined
                        ? details.articleTotalViewCount
                        : this.selectedArticle.ArticleTotalViewCount,
                    ViewCount: this.normalizeViewCount(this.selectedArticle.ViewCount),
                    bodyContent: details.body || ''
                };
            }
        } catch (error) {
            this.articleDetailError = this.extractErrorMessage(error);
        } finally {
            this.isArticleDetailLoading = false;
        }
    }

    closeArticleModal() {
        this.isArticleModalOpen = false;
        this.selectedArticle = null;
        this.isArticleDetailLoading = false;
        this.articleDetailError = '';
    }

    handleModalBackdropClick(event) {
        if (event.target.classList.contains('article-modal-backdrop')) {
            this.closeArticleModal();
        }
    }

    handleResultsBackdropClick(event) {
        if (event.target.classList.contains('results-overlay-backdrop')) {
            this.clearCategorySelection();
        }
    }

    closeResultsPanel() {
        this.clearCategorySelection();
    }

    clearCategorySelection() {
        this.isResultsPanelOpen = false;
        this.shouldFocusResultsPanel = false;
        this.selectedCategoryId = '';
        this.selectedCategoryName = '';
        this.categoryArticles = [];
        this.isLoadingCategoryArticles = false;
        this.categoryError = '';
    }

    async loadCategoryCounts() {
        try {
            const counts = await getCategoryArticleCounts();
            this.applyCategoryCounts(counts);
        } catch (error) {
            // Keep existing fallback numbers if counts API fails.
            // Article fetch still works independently.
            // Intentionally no toast for passive background refresh.
            // eslint-disable-next-line no-console
            console.error('Unable to load dynamic category counts', error);
        }
    }

    applyCategoryCounts(counts) {
        if (!counts) {
            return;
        }

        this.categories = this.categories.map((category) => {
            const value = counts[category.categoryValue];
            return {
                ...category,
                articles: typeof value === 'number' ? value : category.articles
            };
        });
    }

    async attachCategoryArticleViewCounts(articles) {
        const articleIds = (articles || [])
            .map((article) => article.Id)
            .filter((id) => Boolean(id));

        if (!articleIds.length) {
            return articles;
        }

        try {
            const counts = await getArticleViewCounts({ articleVersionIds: articleIds });

            return articles.map((article) => {
                return {
                    ...article,
                    ViewCount: this.normalizeViewCount(counts ? counts[article.Id] : 0)
                };
            });
        } catch (error) {
            return articles;
        }
    }

    async recordAndApplyViewCount(articleId) {
        if (!articleId) {
            return;
        }

        try {
            const latestCount = await recordArticleView({ articleVersionId: articleId });
            const normalizedCount = this.normalizeViewCount(latestCount);

            this.categoryArticles = this.categoryArticles.map((article) => {
                if (article.Id !== articleId) {
                    return article;
                }

                return {
                    ...article,
                    ViewCount: normalizedCount
                };
            });

            if (this.selectedArticle && this.selectedArticle.Id === articleId) {
                this.selectedArticle = {
                    ...this.selectedArticle,
                    ViewCount: normalizedCount
                };
            }
        } catch (error) {
            // Do not block article preview when tracking update fails.
        }
    }

    normalizeViewCount(value) {
        const numericValue = Number(value);

        if (!Number.isFinite(numericValue) || numericValue < 0) {
            return 0;
        }

        return Math.floor(numericValue);
    }

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }

        return 'Unable to load category articles right now. Please try again.';
    }
}
