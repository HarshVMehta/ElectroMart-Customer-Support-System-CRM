@isTest
public class KnowledgeControllerTest {
    
    @testSetup
    static void setupTestData() {
        // Create test knowledge articles
        // Note: You'll need to adjust based on your Knowledge Article Type name
        // This is a generic example
        
        List<Knowledge__kav> articles = new List<Knowledge__kav>();
        
        for (Integer i = 1; i <= 10; i++) {
            Knowledge__kav article = new Knowledge__kav(
                Title = 'Test Article ' + i,
                Summary = 'Test summary for article ' + i,
                UrlName = 'test-article-' + i
            );
            articles.add(article);
        }
        
        // Insert articles - they will be in draft status
        insert articles;
        
        // Publish the articles
        List<Id> articleIds = new List<Id>();
        for (Knowledge__kav article : articles) {
            articleIds.add(article.Id);
        }
        
        // Use KbManagement to publish
        for (Id articleId : articleIds) {
            KbManagement.PublishingService.publishArticle(articleId, true);
        }
    }
    
    @isTest
    static void testGetPopularArticles() {
        Test.startTest();
        List<Knowledge__kav> articles = KnowledgeController.getPopularArticles(6);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles should not be null');
        System.assert(articles.size() <= 6, 'Should return max 6 articles');
    }
    
    @isTest
    static void testGetPopularArticlesWithNullLimit() {
        Test.startTest();
        List<Knowledge__kav> articles = KnowledgeController.getPopularArticles(null);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Articles should not be null');
        System.assert(articles.size() <= 6, 'Should return default 6 articles');
    }
    
    @isTest
    static void testSearchArticles() {
        Test.startTest();
        List<Knowledge__kav> articles = KnowledgeController.searchArticles('Test', 10);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Search results should not be null');
    }
    
    @isTest
    static void testSearchArticlesWithBlankTerm() {
        Test.startTest();
        List<Knowledge__kav> articles = KnowledgeController.searchArticles('', 10);
        Test.stopTest();
        
        System.assertEquals(0, articles.size(), 'Should return empty list for blank search');
    }
    
    @isTest
    static void testGetArticlesByCategory() {
        Test.startTest();
        List<Knowledge__kav> articles = KnowledgeController.getArticlesByCategory('Mobiles', 10);
        Test.stopTest();
        
        System.assertNotEquals(null, articles, 'Category articles should not be null');
    }
    
    @isTest
    static void testGetArticlesByCategoryWithBlankCategory() {
        Test.startTest();
        List<Knowledge__kav> articles = KnowledgeController.getArticlesByCategory('', 10);
        Test.stopTest();
        
        System.assertEquals(0, articles.size(), 'Should return empty list for blank category');
    }
}