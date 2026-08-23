import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { catchError, firstValueFrom } from 'rxjs';

// URL relative : contrairement à dotnet-angular/ (backend et frontend
// séparés, deux ports, CORS nécessaire), ici Angular est servi par le même
// process ASP.NET Core que l'API (voir Program.cs) — même origine, pas
// besoin d'URL absolue ni de CORS.
const API_BASE = '';

export interface PathResult {
  path: string[];
  found: boolean;
}

export class PathNotFoundError extends Error {}
export class PathApiError extends Error {}

@Injectable({ providedIn: 'root' })
export class PathApiService {
  constructor(private readonly http: HttpClient) {}

  async findPath(source: string, target: string): Promise<PathResult> {
    const url = `${API_BASE}/api/path?source=${encodeURIComponent(source)}&target=${encodeURIComponent(target)}`;

    return firstValueFrom(
      this.http.get<PathResult>(url).pipe(
        catchError((err: HttpErrorResponse) => {
          if (err.status === 404) {
            throw new PathNotFoundError(err.error?.detail ?? 'Aucun chemin trouvé.');
          }
          throw new PathApiError(err.error?.detail ?? `Erreur API (${err.status})`);
        }),
      ),
    );
  }
}
