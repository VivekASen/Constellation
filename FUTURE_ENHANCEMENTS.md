# Future Enhancements

Last updated: 2026-03-04

## Deferred Integrations

### OverDrive (Library Borrowing)
Status: Deferred
Priority: Medium

Why deferred now:
- Product focus is current podcast/book UX and metadata pipeline.
- OverDrive requires partner onboarding/application and auth flows that add non-trivial scope.

Why revisit:
- Strong ethical option: borrow from libraries instead of only buying.
- Fits Constellation's research/discovery mission.

When we revisit:
1. Complete OverDrive developer application/approval.
2. Add optional library account linking.
3. Add "Library Availability" section in book detail.
4. Add hold/borrow actions only after availability is stable.

References:
- https://developer.overdrive.com/getting-started/api-overview
- https://developer.overdrive.com/getting-started/application-process

---

## Book Experience

### In-app Ebook Reading (DRM-free only)
Status: Deferred
Priority: Low-Medium

Notes:
- Possible for EPUB/PDF imports and DRM-free sources.
- Not feasible for DRM-locked Apple Books/Kindle content.
- Could be built later with reading position + highlight sync.

---

## Storefront & Availability UX

### Multi-edition thrift buying helper
Status: Future Idea
Priority: Medium

Notes:
- Current behavior uses title+author search on ThriftBooks.
- Future: store multiple ISBNs/editions and provide in-app edition picker for faster in-stock path.
