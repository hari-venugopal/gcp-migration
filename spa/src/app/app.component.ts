import { Component, OnInit, inject, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { SPA_BUILD } from './build-info';

interface Item {
  id: number;
  name: string;
  createdAt: string;
}

interface Health {
  status: string;
  version: string;
  revision: string;
}

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [FormsModule],
  template: `
    <main>
      <h1>Amaze GCP Lab</h1>

      <section class="versions">
        <span>SPA release: <strong>{{ spaBuild }}</strong></span>
        @if (health(); as h) {
          <span>API revision: <strong>{{ h.revision }}</strong> ({{ h.version }})</span>
        } @else {
          <span class="error">{{ error() || 'Checking API...' }}</span>
        }
        <button type="button" (click)="refresh()">Refresh</button>
      </section>

      <form (ngSubmit)="add()">
        <input name="name" [(ngModel)]="newName" placeholder="New item" maxlength="200" />
        <button type="submit" [disabled]="!newName.trim()">Add</button>
      </form>

      <ul>
        @for (item of items(); track item.id) {
          <li>
            <span>{{ item.name }}</span>
            <button type="button" (click)="remove(item.id)">Delete</button>
          </li>
        } @empty {
          <li class="empty">No items yet.</li>
        }
      </ul>
    </main>
  `,
  styles: [`
    main { max-width: 640px; margin: 40px auto; padding: 0 16px; }
    .versions { display: flex; flex-wrap: wrap; gap: 16px; align-items: center; padding: 12px;
                background: #fff; border: 1px solid #dde1e7; border-radius: 8px; font-size: 14px; }
    .error { color: #b3261e; }
    form { display: flex; gap: 8px; margin: 24px 0 12px; }
    input { flex: 1; padding: 8px; border: 1px solid #c4cad3; border-radius: 6px; }
    button { padding: 8px 12px; border: 0; border-radius: 6px; background: #1a5fb4; color: #fff; cursor: pointer; }
    button:disabled { opacity: .5; cursor: default; }
    ul { list-style: none; padding: 0; }
    li { display: flex; justify-content: space-between; align-items: center; padding: 10px 12px;
         background: #fff; border: 1px solid #dde1e7; border-radius: 6px; margin-bottom: 6px; }
    .empty { color: #667085; }
  `],
})
export class AppComponent implements OnInit {
  private readonly http = inject(HttpClient);

  readonly spaBuild = SPA_BUILD;
  readonly items = signal<Item[]>([]);
  readonly health = signal<Health | null>(null);
  readonly error = signal('');
  newName = '';

  ngOnInit(): void {
    this.refresh();
  }

  refresh(): void {
    this.http.get<Health>('/api/health').subscribe({
      next: (h) => { this.health.set(h); this.error.set(''); },
      error: () => { this.health.set(null); this.error.set('API unreachable'); },
    });
    this.http.get<Item[]>('/api/items').subscribe({
      next: (items) => this.items.set(items),
      error: () => this.items.set([]),
    });
  }

  add(): void {
    const name = this.newName.trim();
    if (!name) return;
    this.http.post<Item>('/api/items', { name }).subscribe(() => {
      this.newName = '';
      this.refresh();
    });
  }

  remove(id: number): void {
    this.http.delete(`/api/items/${id}`).subscribe(() => this.refresh());
  }
}
