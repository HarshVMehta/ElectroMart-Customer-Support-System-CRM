public with sharing class KnowledgeController {
    
    /**
     * Get popular knowledge articles based on view count
     * @param limitCount - Number of articles to return
     * @return List of Knowledge articles
     */
    @AuraEnabled(cacheable=true)
    public static List<Knowledge__kav> getPopularArticles(Integer limitCount) {
        try {
            if (limitCount == null || limitCount <= 0) {
                limitCount = 6;
            }
            
            // Query published knowledge articles ordered by view count
            List<Knowledge__kav> articles = [
                SELECT Id, Title, Summary, UrlName, ArticleNumber, 
                       ArticleTotalViewCount
                FROM Knowledge__kav
                WHERE PublishStatus = 'Online' 
                AND Language = 'en_US'
                ORDER BY ArticleTotalViewCount DESC NULLS LAST
                LIMIT :limitCount
            ];
            
            return articles;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching articles: ' + e.getMessage());
        }
    }
    
    /**
     * Search knowledge articles by keyword
     * @param searchTerm - Search keyword
     * @param limitCount - Number of results to return
     * @return List of matching Knowledge articles
     */
    @AuraEnabled(cacheable=true)
    public static List<Knowledge__kav> searchArticles(String searchTerm, Integer limitCount) {
        try {
            if (String.isBlank(searchTerm)) {
                return new List<Knowledge__kav>();
            }
            
            if (limitCount == null || limitCount <= 0) {
                limitCount = 10;
            }
            
            String searchQuery = '%' + searchTerm + '%';
            
            List<Knowledge__kav> articles = [
                SELECT Id, Title, Summary, UrlName, ArticleNumber,
                       ArticleTotalViewCount
                FROM Knowledge__kav
                WHERE PublishStatus = 'Online'
                AND Language = 'en_US'
                AND (Title LIKE :searchQuery OR Summary LIKE :searchQuery)
                ORDER BY ArticleTotalViewCount DESC NULLS LAST
                LIMIT :limitCount
            ];
            
            return articles;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error searching articles: ' + e.getMessage());
        }
    }
    
    /**
     * Get articles by category
     * @param category - Product category
     * @param limitCount - Number of results to return
     * @return List of Knowledge articles
     */
    @AuraEnabled(cacheable=true)
    public static List<Knowledge__kav> getArticlesByCategory(String category, Integer limitCount) {
        try {
            if (String.isBlank(category)) {
                return new List<Knowledge__kav>();
            }
            
            if (limitCount == null || limitCount <= 0) {
                limitCount = 10;
            }
            
            // Assuming you have a Category__c field on Knowledge__kav
            List<Knowledge__kav> articles = [
                SELECT Id, Title, Summary, UrlName, ArticleNumber,
                       ArticleTotalViewCount
                FROM Knowledge__kav
                WHERE PublishStatus = 'Online'
                AND Language = 'en_US'
                AND Category__c = :category
                ORDER BY ArticleTotalViewCount DESC NULLS LAST
                LIMIT :limitCount
            ];
            
            return articles;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching category articles: ' + e.getMessage());
        }
    }
}