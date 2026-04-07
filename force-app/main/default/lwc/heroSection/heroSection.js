import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchArticles from '@salesforce/apex/KnowledgeController.searchArticles';
import getArticleDetails from '@salesforce/apex/KnowledgeController.getArticleDetails';
import getArticleViewCounts from '@salesforce/apex/KnowledgeController.getArticleViewCounts';
import recordArticleView from '@salesforce/apex/KnowledgeController.recordArticleView';

export default class HeroSection extends NavigationMixin(LightningElement) {
    @api webToCasePath = '/case-form';

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
    activeSearchRequestId = 0;

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
            this.activeSearchRequestId += 1;
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
        const requestId = this.activeSearchRequestId + 1;
        this.activeSearchRequestId = requestId;
        this.isSearching = true;
        this.showResultsPanel = true;
        this.searchError = '';

        try {
            const results = await searchArticles({
                searchTerm: keyword,
                limitCount: 6
            });

            if (requestId !== this.activeSearchRequestId) {
                return;
            }

            const normalizedResults = (results || []).map((article) => {
                return {
                    ...article,
                    safeSummary: article.Summary || 'No summary available yet.',
                    ViewCount: 0
                };
            });

            this.searchResults = await this.attachArticleViewCounts(normalizedResults);
        } catch (error) {
            this.searchResults = [];
            this.searchError = this.extractErrorMessage(error);
        } finally {
            if (requestId === this.activeSearchRequestId) {
                this.isSearching = false;
            }
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
            ViewCount: this.normalizeViewCount(selected.ViewCount),
            bodyContent: ''
        };
        this.isArticleModalOpen = true;
        this.showResultsPanel = false;
        this.articleDetailError = '';
        this.isArticleDetailLoading = true;

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

    async attachArticleViewCounts(articles) {
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

            this.searchResults = this.searchResults.map((article) => {
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

    navigateToSupport() {
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: this.webToCasePath
            }
        });
    }
}