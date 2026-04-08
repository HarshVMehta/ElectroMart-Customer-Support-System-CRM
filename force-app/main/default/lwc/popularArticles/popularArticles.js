import { LightningElement } from 'lwc';
import getPopularArticleRankings from '@salesforce/apex/KnowledgeController.getPopularArticleRankings';
import recordArticleView from '@salesforce/apex/KnowledgeController.recordArticleView';
import getArticleDetails from '@salesforce/apex/KnowledgeController.getArticleDetails';

const TOP_ARTICLES_LIMIT = 6;
const REFRESH_INTERVAL_MS = 15000;
const ALL_ARTICLES_CACHE_MS = 15000;

export default class PopularArticles extends LightningElement {
    articles = [];
    allArticles = [];
    error = '';
    isLoading = true;
    refreshTimerId;
    activeTopLoadRequestId = 0;

    isAllPanelOpen = false;
    isAllPanelLoading = false;
    allPanelError = '';
    activeAllLoadRequestId = 0;
    lastAllLoadedAt = 0;

    isArticleModalOpen = false;
    selectedArticle = null;
    isArticleDetailLoading = false;
    articleDetailError = '';
    activeModalRequestId = 0;

    connectedCallback() {
        this.loadTopArticles(true);
        this.startAutoRefresh();
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
    }

    get hasArticles() {
        return this.articles.length > 0;
    }

    get hasError() {
        return Boolean(this.error);
    }

    get rankingSummary() {
        const articleCount = this.articles.length;
        const articleText = articleCount === 1 ? 'article' : 'articles';
        return `Showing top ${articleCount} ${articleText} by live views`;
    }

    get viewAllButtonLabel() {
        return 'View All Articles';
    }

    get hasAllArticles() {
        return this.allArticles.length > 0;
    }

    get hasAllPanelError() {
        return Boolean(this.allPanelError);
    }

    get allPanelSummary() {
        const count = this.allArticles.length;
        const noun = count === 1 ? 'article' : 'articles';
        return `${count} ranked ${noun} (real-time)`;
    }

    get hasArticleDetailError() {
        return Boolean(this.articleDetailError);
    }

    get liveStatusText() {
        return 'Live ranking updates every 15 seconds';
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
        if (!this.selectedArticle || typeof this.selectedArticle.ViewCount !== 'number') {
            return 0;
        }

        return this.selectedArticle.ViewCount;
    }

    get selectedArticleRank() {
        if (!this.selectedArticle || !this.selectedArticle.Rank) {
            return 'N/A';
        }

        return this.selectedArticle.Rank;
    }

    async loadTopArticles(showLoader) {
        const requestId = this.activeTopLoadRequestId + 1;
        this.activeTopLoadRequestId = requestId;

        if (showLoader) {
            this.isLoading = true;
        }

        this.error = '';

        try {
            const rankedArticles = await getPopularArticleRankings({ limitCount: TOP_ARTICLES_LIMIT });

            if (requestId !== this.activeTopLoadRequestId) {
                return;
            }

            this.articles = this.normalizeRankedArticles(rankedArticles || []);
        } catch (error) {
            if (requestId !== this.activeTopLoadRequestId) {
                return;
            }

            this.articles = [];
            this.error = this.extractRankingErrorMessage(error);
        } finally {
            if (requestId === this.activeTopLoadRequestId) {
                this.isLoading = false;
            }
        }
    }

    async loadAllArticles(showLoader, forceRefresh) {
        const hasFreshCache = this.allArticles.length > 0
            && (Date.now() - this.lastAllLoadedAt) < ALL_ARTICLES_CACHE_MS;

        if (!forceRefresh && hasFreshCache) {
            return;
        }

        const requestId = this.activeAllLoadRequestId + 1;
        this.activeAllLoadRequestId = requestId;

        if (showLoader) {
            this.isAllPanelLoading = true;
        }

        this.allPanelError = '';

        try {
            const rankedArticles = await getPopularArticleRankings({ limitCount: null });

            if (requestId !== this.activeAllLoadRequestId) {
                return;
            }

            this.allArticles = this.normalizeRankedArticles(rankedArticles || []);
            this.lastAllLoadedAt = Date.now();
        } catch (error) {
            if (requestId !== this.activeAllLoadRequestId) {
                return;
            }

            this.allPanelError = this.extractRankingErrorMessage(error);
        } finally {
            if (requestId === this.activeAllLoadRequestId) {
                this.isAllPanelLoading = false;
            }
        }
    }

    normalizeRankedArticles(rankedArticles) {
        return rankedArticles.map((article) => {
            return {
                Id: article.id,
                Title: article.title,
                Summary: article.summary,
                safeSummary: article.summary || 'No summary available yet.',
                UrlName: article.urlName,
                ArticleNumber: article.articleNumber || 'N/A',
                ViewCount: this.normalizeViewCount(article.viewCount),
                Rank: article.rank || 0,
                rankBadgeClass: 'rank-badge'
            };
        });
    }

    async handleArticleClick(event) {
        const articleId = event.currentTarget.dataset.id;
        const article = this.findArticleById(articleId);

        if (!article) {
            return;
        }

        const requestId = this.activeModalRequestId + 1;
        this.activeModalRequestId = requestId;

        this.selectedArticle = {
            ...article,
            bodyContent: ''
        };
        this.isArticleModalOpen = true;
        this.isArticleDetailLoading = true;
        this.articleDetailError = '';

        await this.loadArticleDetails(article.Id, requestId);

        if (requestId === this.activeModalRequestId) {
            this.isArticleDetailLoading = false;
        }

        this.recordViewForArticle(article.Id, requestId);
    }

    findArticleById(articleId) {
        const fromTopArticles = this.articles.find((art) => art.Id === articleId);
        if (fromTopArticles) {
            return fromTopArticles;
        }

        return this.allArticles.find((art) => art.Id === articleId);
    }

    viewAllArticles() {
        this.isAllPanelOpen = true;
        this.loadAllArticles(true, false);
    }

    closeAllPanel() {
        this.isAllPanelOpen = false;
    }

    handleAllPanelBackdropClick(event) {
        if (event.target.classList.contains('all-panel-backdrop')) {
            this.closeAllPanel();
        }
    }

    startAutoRefresh() {
        if (typeof window === 'undefined') {
            return;
        }

        this.stopAutoRefresh();

        this.refreshTimerId = window.setInterval(() => {
            this.loadTopArticles(false);

            if (this.isAllPanelOpen) {
                this.loadAllArticles(false, true);
            }
        }, REFRESH_INTERVAL_MS);
    }

    stopAutoRefresh() {
        if (typeof window === 'undefined' || !this.refreshTimerId) {
            return;
        }

        window.clearInterval(this.refreshTimerId);
        this.refreshTimerId = null;
    }

    async recordViewForArticle(articleId, requestId) {
        try {
            await recordArticleView({ articleVersionId: articleId });

            // UI shows tracked popup views, so apply a +1 optimistic update locally.
            // A background refresh reconciles final server order/counts.
            this.applyIncrementedViewCount(articleId, requestId);
            this.loadTopArticles(false);

            if (this.isAllPanelOpen) {
                this.loadAllArticles(false, true);
            }
        } catch (error) {
            // View tracking failure should not block article reading.
        }
    }

    async loadArticleDetails(articleId, requestId) {
        try {
            const details = await getArticleDetails({ articleVersionId: articleId });

            if (requestId !== this.activeModalRequestId || !details || !this.selectedArticle || this.selectedArticle.Id !== articleId) {
                return;
            }

            this.selectedArticle = {
                ...this.selectedArticle,
                Title: details.title || this.selectedArticle.Title,
                Summary: details.summary || this.selectedArticle.Summary,
                safeSummary: details.summary || this.selectedArticle.safeSummary,
                UrlName: details.urlName || this.selectedArticle.UrlName,
                ArticleNumber: details.articleNumber || this.selectedArticle.ArticleNumber,
                bodyContent: details.body || ''
            };
        } catch (error) {
            if (requestId === this.activeModalRequestId) {
                this.articleDetailError = this.extractArticleErrorMessage(error);
            }
        }
    }

    applyIncrementedViewCount(articleId, requestId) {
        this.articles = this.updateRankedCollection(this.articles, articleId);
        this.allArticles = this.updateRankedCollection(this.allArticles, articleId);

        if (requestId !== this.activeModalRequestId) {
            return;
        }

        if (this.selectedArticle && this.selectedArticle.Id === articleId) {
            const currentCount = this.normalizeViewCount(this.selectedArticle.ViewCount);
            this.selectedArticle = {
                ...this.selectedArticle,
                ViewCount: currentCount + 1
            };
        }
    }

    updateRankedCollection(collection, articleId) {
        if (!collection || !collection.length) {
            return collection;
        }

        let wasUpdated = false;

        const patched = collection.map((article) => {
            if (article.Id !== articleId) {
                return article;
            }

            wasUpdated = true;
            const currentCount = this.normalizeViewCount(article.ViewCount);

            return {
                ...article,
                ViewCount: currentCount + 1
            };
        });

        if (!wasUpdated) {
            return patched;
        }

        patched.sort((left, right) => {
            const byViews = (right.ViewCount || 0) - (left.ViewCount || 0);
            if (byViews !== 0) {
                return byViews;
            }

            const leftTitle = (left.Title || '').toLowerCase();
            const rightTitle = (right.Title || '').toLowerCase();
            return leftTitle.localeCompare(rightTitle);
        });

        return patched.map((article, index) => {
            return {
                ...article,
                Rank: index + 1,
                rankBadgeClass: 'rank-badge'
            };
        });
    }

    closeArticleModal() {
        this.activeModalRequestId += 1;
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

    normalizeViewCount(value) {
        const numericValue = Number(value);

        if (!Number.isFinite(numericValue) || numericValue < 0) {
            return 0;
        }

        return Math.floor(numericValue);
    }

    extractRankingErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }

        return 'Unable to load ranked articles right now. Please try again.';
    }

    extractArticleErrorMessage(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }

        return 'Unable to load article details right now. Please try again.';
    }
}