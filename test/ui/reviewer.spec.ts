import { expect, test } from '@playwright/test';

test('reviewer can navigate and save each kind of decision', async ({ page }, testInfo) => {
  await page.goto('/reviews');
  await expect(page.locator('#login_form_magic')).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('login.png'), fullPage: true });

  await page.goto(process.env.UI_MAGIC_LINK!);
  await page.locator('#login_form button').last().click();
  await page.goto('/reviews');
  await expect(page.locator('#reviewer-workspace')).toBeVisible();
  await expect(page.locator('#works tbody tr')).toHaveCount(16);
  await expect(page.locator('#links a')).toHaveCount(1);
  await page.screenshot({ path: testInfo.outputPath('workspace.png'), fullPage: true });

  await page.goto('/reviews/works/T1800');
  await expect(page.locator('#work-review-form')).toBeVisible();
  await expect(page.locator('#work-review-form button')).toHaveClass(/btn-primary/);
  await page.screenshot({ path: testInfo.outputPath('work.png'), fullPage: true });
  await page.locator('[name="work_review[judgment]"]').selectOption('needs_review');
  await page.locator('[name="work_review[rationale]"]').fill('Synthetic catalogue attribution requires verification.');
  await page.locator('[name="work_review[source_references]"]').fill('Synthetic T1800 catalogue');
  await page.locator('#work-review-form button').click();
  await expect(page.getByText('Synthetic catalogue attribution requires verification.')).toBeVisible();

  await page.goto('/reviews');
  await page.locator('#links a').first().click();
  await expect(page.locator('#link-review-form')).toBeVisible();
  await expect(page.locator('#link-review-form button')).toHaveClass(/btn-primary/);
  await page.screenshot({ path: testInfo.outputPath('link.png'), fullPage: true });
  await page.locator('[name="review[judgment]"]').selectOption('disputed');
  await page.locator('[name="review[rationale]"]').fill('Synthetic shared wording does not establish direction.');
  await page.locator('[name="review[source_references]"]').fill('Synthetic T1800 and T0400 passages');
  await page.locator('#link-review-form button').click();
  await expect(page.getByText('Synthetic shared wording does not establish direction.')).toBeVisible();

  await page.goto('/reviews/rights');
  await expect(page.locator('#rights-review-page')).toBeVisible();
  await expect(page.locator('a[id^="right-"]')).toHaveCount(20);
  await page.screenshot({ path: testInfo.outputPath('rights.png'), fullPage: true });
  await page.locator('a[id^="right-"]').first().click();
  await expect(page.locator('#rights-decision-form button')).toHaveClass(/btn-primary/);
  await page.screenshot({ path: testInfo.outputPath('rights-item.png'), fullPage: true });
  await page.locator('[name="rights_review[decision]"]').selectOption('unresolved');
  await page.locator('[name="rights_review[rationale]"]').fill('Synthetic fixture has no permission evidence.');
  await page.locator('[name="rights_review[evidence_references]"]').fill('Synthetic fixture terms');
  await page.locator('#rights-decision-form button').click();
  await expect(page.getByText('Synthetic fixture has no permission evidence.')).toBeVisible();

  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto('/reviews');
  await expect(page.locator('#reviewer-workspace')).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('workspace-mobile.png'), fullPage: true });
});
