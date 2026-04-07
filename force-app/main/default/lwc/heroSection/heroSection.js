import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchArticles from '@salesforce/apex/KnowledgeController.searchArticles';
import getArticleDetails from '@salesforce/apex/KnowledgeController.getArticleDetails';

export default class HeroSection extends NavigationMixin(LightningElement) {
    searchQuery = '';
    searchResults = [];
    isSearching = false;
    showResultsPanel = false;
    searchError = '';

    isArticleModalOpen = false;
    selectedArticle = null;
    isArticleDetailLoading = false;
    articleDetailError = '';

    searchDebounceTimer;

    disconnectedCallback() {
        if (typeof window !== 'undefined') {
            window.clearTimeout(this.searchDebounceTimer);
        }
    }

    handleSearchInput(event) {
        this.searchQuery = event.target.value;

        const normalizedQuery = this.searchQuery.trim();
        this.searchError = '';

        if (normalizedQuery.length < 2) {
            this.searchResults = [];
            this.isSearching = false;
            this.showResultsPanel = false;
            return;
        }

        if (typeof window !== 'undefined') {
            window.clearTimeout(this.searchDebounceTimer);
            this.searchDebounceTimer = window.setTimeout(() => {
                this.fetchArticles(normalizedQuery);
            }, 350);
        }
    }

    handleSearch() {
        const normalizedQuery = this.searchQuery.trim();

        if (normalizedQuery.length < 2) {
            this.showResultsPanel = true;
            this.searchResults = [];
            this.searchError = 'Type at least 2 characters to search knowledge articles.';
            return;
        }

        this.fetchArticles(normalizedQuery);
    }

    handleKeyPress(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleSearch();
        }
    }

    async fetchArticles(keyword) {
        this.isSearching = true;
        this.showResultsPanel = true;
        this.searchError = '';

        try {
            const results = await searchArticles({
                searchTerm: keyword,
                limitCount: 6
            });

            this.searchResults = (results || []).map((article) => {
                return {
                    ...article,
                    safeSummary: article.Summary || 'No summary available yet.'
                };
            });
        } catch (error) {
            this.searchResults = [];
            this.searchError = this.extractErrorMessage(error);
        } finally {
            this.isSearching = false;
        }
    }

    async handleResultClick(event) {
        const articleId = event.currentTarget.dataset.id;
        const selected = this.searchResults.find((article) => article.Id === articleId);

        if (!selected) {
            return;
        }

        this.selectedArticle = {
            ...selected,
            bodyContent: ''
        };
        this.isArticleModalOpen = true;
        this.showResultsPanel = false;
        this.articleDetailError = '';
        this.isArticleDetailLoading = true;

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

    extractErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }

        return 'Unable to fetch articles right now. Please try again.';
    }

    get hasResults() {
        return this.searchResults.length > 0;
    }

    get showNoResults() {
        return !this.isSearching && !this.searchError && this.showResultsPanel && !this.hasResults;
    }

    get hasSearchError() {
        return Boolean(this.searchError);
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
        if (!this.selectedArticle || !this.selectedArticle.ArticleTotalViewCount) {
            return 0;
        }

        return this.selectedArticle.ArticleTotalViewCount;
    }

    get hasArticleDetailError() {
        return Boolean(this.articleDetailError);
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