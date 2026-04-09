import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class SupportGlobalHeader extends NavigationMixin(LightningElement) {
    @api brandName = 'ElectroMart Support';
    @api homePath = '/';
    @api homePageApiName = 'Home';
    @api caseFormPath = '/case-form';
    @api caseTrackingPath = '/case-tracking';

    isMenuOpen = false;
    currentPath = '/';

    popStateHandler;

    connectedCallback() {
        this.syncCurrentPath();

        if (typeof window !== 'undefined') {
            this.popStateHandler = () => {
                this.syncCurrentPath();
            };
            window.addEventListener('popstate', this.popStateHandler);
        }
    }

    disconnectedCallback() {
        if (typeof window !== 'undefined' && this.popStateHandler) {
            window.removeEventListener('popstate', this.popStateHandler);
        }
    }

    get computedNavClass() {
        return this.isMenuOpen ? 'nav-links open' : 'nav-links';
    }

    get normalizedHomePath() {
        return this.normalizePath(this.homePath, '/');
    }

    get normalizedCaseFormPath() {
        return this.normalizePath(this.caseFormPath, '/case-form');
    }

    get normalizedCaseTrackingPath() {
        return this.normalizePath(this.caseTrackingPath, '/case-tracking');
    }

    get navItems() {
        return [
            {
                key: 'home',
                label: 'Home',
                icon: 'utility:home',
                path: this.normalizedHomePath
            },
            {
                key: 'case-form',
                label: 'Case Form',
                icon: 'utility:file',
                path: this.normalizedCaseFormPath
            },
            {
                key: 'case-tracking',
                label: 'Track Case',
                icon: 'utility:trail',
                path: this.normalizedCaseTrackingPath
            }
        ].map((item) => {
            const isActive = this.isPathActive(item.path);
            return {
                ...item,
                className: isActive ? 'nav-link active' : 'nav-link',
                ariaCurrent: isActive ? 'page' : null
            };
        });
    }

    toggleMenu() {
        this.isMenuOpen = !this.isMenuOpen;
    }

    handleNavigate(event) {
        const targetPath = event.currentTarget.dataset.path;
        const targetKey = event.currentTarget.dataset.key;
        if (!targetPath) {
            return;
        }

        this.isMenuOpen = false;

        if (this.isPathActive(targetPath)) {
            return;
        }

        if (targetKey === 'home') {
            this.navigateToHome(targetPath);
            return;
        }

        this.navigateToPath(targetPath);
    }

    navigateToHome(fallbackPath) {
        const pageName = (this.homePageApiName || '').trim();

        if (pageName) {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: pageName
                }
            });
            return;
        }

        this.navigateToPath(fallbackPath);
    }

    navigateToPath(targetPath) {
        if (!targetPath) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: targetPath
            }
        });
    }

    syncCurrentPath() {
        if (typeof window === 'undefined') {
            this.currentPath = '/';
            return;
        }

        const pathName = window.location && window.location.pathname
            ? window.location.pathname
            : '/';

        this.currentPath = this.stripTrailingSlash(pathName.toLowerCase());
    }

    normalizePath(inputValue, fallbackPath) {
        const rawValue = (inputValue || '').trim();

        if (!rawValue) {
            return fallbackPath;
        }

        if (rawValue.startsWith('http://') || rawValue.startsWith('https://')) {
            return rawValue;
        }

        if (rawValue.startsWith('/')) {
            return rawValue;
        }

        return `/${rawValue}`;
    }

    isPathActive(targetPath) {
        if (!targetPath || targetPath.startsWith('http://') || targetPath.startsWith('https://')) {
            return false;
        }

        const current = this.stripTrailingSlash(this.currentPath);
        const target = this.stripTrailingSlash(targetPath.toLowerCase());

        if (target === '/') {
            return current === '/' || current === '/s' || current.endsWith('/s');
        }

        return current === target || current.endsWith(target) || current.includes(`/s${target}`);
    }

    stripTrailingSlash(pathValue) {
        const value = (pathValue || '').trim();

        if (!value || value === '/') {
            return '/';
        }

        return value.replace(/\/+$/, '');
    }
}
